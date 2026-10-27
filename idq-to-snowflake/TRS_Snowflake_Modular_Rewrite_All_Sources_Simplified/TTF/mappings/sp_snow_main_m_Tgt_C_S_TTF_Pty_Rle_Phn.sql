-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn  --  MODULAR REWRITE (simplified v2 style)
--
-- IDQ mapping: m_Tgt_C_S_TTF_Pty_Rle_Phn, workflow wf_TTF_Stage_Load
-- (fourth mapping in the workflow run order, after Pty_Rle_Alt_Id).
--
-- Business flow, in plain words: one phone per active TTF client into
-- C_S_TTF_PTY_RLE_PHN.  Active means the party is not in the
-- inactive-status table with a status set (maintained by Pty_Validation,
-- which runs first); phones that are NULL never load.  Each phone is
-- standardised and validated (area-code check included): a good phone
-- loads as usage '001', type 'Telephone', preference 'Primary'; a bad
-- phone is NOT loaded, only logged as a 'Rejected Record' exception
-- with the source phone as the attribute value.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> checked ->
--   final), one transaction, one log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE transaction,
--   so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TTF_PHN_S1_SRC      phones of active clients only
--                                    (NULL phones and inactive parties
--                                    filtered out) + phone key +
--                                    standardised phone
--   Step 20  WRK_TTF_PHN_S2_CHECKED  phone validation code (area-code
--                                    lookup included)
--   Step 30  WRK_TTF_PHN_S3_ROUTED   exception description, constants,
--                                    and insert-only guards
--   Step 40  PUBLISH                targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_TTF_PHN_S1_SRC, WRK_TTF_PHN_S2_CHECKED, WRK_TTF_PHN_S3_ROUTED.
--   They live in the install schema (unqualified names, as in the
--   original code): schema TTF_ETL_WRK in database MDM_ETL_TTF.
--   They survive a session crash (TRANSIENT, not TEMP), which is what
--   makes inspection after a run possible.  No CURSOR was used: every
--   step here is set-based by design -- the work table IS the result
--   set, held as a table instead of in memory, so it can be counted
--   and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  PRESERVED: the IDQ "truncate target table"
--     of C_S_TTF_PTY_RLE_PHN is NOT performed; keys already present are
--     skipped by the uq_phn guard instead.
--   * PRESERVED: Bad_Phone_Ext records never occur -- the extension port
--     feeding the extension standardisation rule is not fed in IDQ, so
--     that rule returns no code -- and no such branch is generated here.
--   * PRESERVED: the exception row's SRC_SYS_ID_2 is NULL (linked in
--     IDQ to a router port without input, ID_PHONE).
--   * PRESERVED: the source read stores an invalid SQL fragment
--     ("PHONE" in ()) that is not in custom-query mode, so it is not
--     applied -- no such filter appears in this rewrite either.
--   * PRESERVED: unique keys Snowflake does not enforce are applied:
--     C_S_TTF_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ) and
--     EXC_STG_BAD_REC_MEMB, via the uq_phn / uq_phone_exc flags.
--   * PRESERVED: VERSION_SEQ = '1'; PERIOD_START_DATE = SUBMITDATE.
--   * The phone area-code lookup is the shared helper
--     fn_snow_helper44_common; its underlying table location is owned
--     by the shared framework (not qualified here, as in the original).
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order (the
--   original took no parameters), so every existing CALL still works.
--   One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'TTF';
    c_workflow   VARCHAR DEFAULT 'wf_TTF_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty_Rle_Phn';
    l_run_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_summary    VARCHAR DEFAULT '';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    -- A run id is generated here (not inside sp_etl_job_begin) so that
    -- the mapping can use it in its own checkpoints without having to
    -- assign the result of a CALL, which Snowflake scripting does not
    -- support as an expression.  sp_etl_job_begin then only logs it.
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        -- l_job_run_id is still NULL at this point: fill it from the
        -- parameter, or generate one.
        l_job_run_id := COALESCE(NULLIF(:P_JOB_RUN_ID, ''),
            'TTF_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_TTF_PHN_S1_SRC;
    DROP TABLE IF EXISTS WRK_TTF_PHN_S2_CHECKED;
    DROP TABLE IF EXISTS WRK_TTF_PHN_S3_ROUTED;

    -- ---- Step 10: SOURCE PHONES -----------------------------------------
    -- Purpose: the phones that may load at all -- non-NULL phones of
    -- clients whose party key is NOT in the inactive-status table with
    -- a status set -- each with its phone key (party key + '|Member|
    -- Telephone|001|' + phone) and its standardised phone number.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PHN_S1_SRC AS
    SELECT v.PHONE, v.SUBMITDATE, v.PTY_SRC_KEY,
           NVL(v.PTY_SRC_KEY, '') || '|Member|Telephone|001|' || v.PHONE AS phn_pkey,
           fn_snow_helper23_common(v.PHONE)                             AS std_phone
      FROM V_TTF_ETL_SRC v
     WHERE v.PHONE IS NOT NULL                                           -- Filt_null_phone
       AND NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i          -- fil_deactivated_status
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PHN_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PHN_S1_SRC', 'CREATED',
        'Non-NULL phones of active clients only, with phone key and standardised phone number. '
        || 'Read by the validation step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC', :l_rows) || CHR(10);

    -- ---- Step 20: VALIDATE PHONES ---------------------------------------
    -- Purpose: the phone validation code for every candidate phone,
    -- from the standardised number, the source, the usage type and the
    -- area-code lookup (first three digits of the standardised phone).
    -- A NULL code means the phone is good; any code means it is a bad
    -- phone that will be logged, not loaded.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PHN_S2_CHECKED AS
    WITH
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common()))
    SELECT s.*,
           /* VALIDATION */ fn_snow_helper24_common(s.std_phone, 'TTF', '001', ar.NPA_ID, ar.SERVICE) AS phone_exception_code
      FROM WRK_TTF_PHN_S1_SRC s
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(s.std_phone, 1, 3);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PHN_S2_CHECKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'CHECKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PHN_S2_CHECKED', 'CREATED',
        'Phone validation code attached to every candidate phone (NULL = good phone, a code = bad phone). '
        || 'Read by the router step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 CHECKED', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTER + GUARDS ---------------------------------------
    -- Purpose: the publish-ready rows.  The exception description is
    -- resolved, constants are attached (version, hub state, role key,
    -- phone type, usage type, preference level), and the insert-only
    -- guards are computed: uq_phn skips phone keys already in the phone
    -- target (first row per key in this run wins, separately for good
    -- and bad phones), and uq_phone_exc keeps one exception row per
    -- party per phone code.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PHN_S3_ROUTED AS
    WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT c.*,
           xp.EXCEPTION_DESC                                    AS phone_exception_desc,
           '1' /* TIMELINE: VERSION_SEQ */                     AS version_seq,
           1                                                    AS hub_state_ind,
           NVL(c.PTY_SRC_KEY, '') || '|Member'                  AS pty_rle_fk,
           'Telephone'                                          AS phn_tp,
           '001'                                                AS usg_tp,
           'Primary'                                            AS pref_lvl,
           'TTF'                                                AS src_sys,
           :l_run_ts                                            AS run_ts,
           :c_mapping                                           AS mapping_name,
           'Rejected Record'                                    AS exc_type_rejected,
           'Main Phone'                                         AS attr_phone,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY c.phone_exception_code IS NULL, c.phn_pkey
                                   ORDER BY c.SUBMITDATE DESC) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL)                    AS uq_phn,
           ROW_NUMBER() OVER (PARTITION BY c.phone_exception_code IS NULL, c.PTY_SRC_KEY, c.phone_exception_code
                                  ORDER BY c.SUBMITDATE DESC) = 1 AS uq_phone_exc
      FROM WRK_TTF_PHN_S2_CHECKED c
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = c.phn_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PHN_S3_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PHN_S3_ROUTED', 'CREATED',
        'Publish-ready rows: exception description, constants, and insert-only guards uq_phn / uq_phone_exc. '
        || 'Published in step 40.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 40: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-30 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning.  The two INSERTs below are the
    -- two branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHERE conditions -- only the
    -- source changed, from the final SELECT to step 30.
    BEGIN TRANSACTION;
    -- 40a. RTR_Valid_PhoneNumbers.Good_Records -> Write_C_S_TTF_PTY_RLE_PHN
    INSERT INTO C_S_TTF_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
            PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT)
    SELECT phn_pkey, SUBMITDATE, version_seq, run_ts, phn_pkey, hub_state_ind, pty_rle_fk, phn_tp, usg_tp,
           std_phone, pref_lvl, SUBMITDATE
      FROM WRK_TTF_PHN_S3_ROUTED
     WHERE phone_exception_code IS NULL AND uq_phn;
    l_rows := SQLROWCOUNT;
    -- 40b. RTR_Valid_PhoneNumbers.Bad_Phone_Records -> write_Phone_Exception
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
            SRC_SYS_ID_2)
    SELECT src_sys, phone_exception_code, phone_exception_desc, run_ts, PHONE, NULL, NULL, mapping_name,
           PTY_SRC_KEY, exc_type_rejected, SUBMITDATE, PHONE, attr_phone, NULL
      FROM WRK_TTF_PHN_S3_ROUTED
     WHERE phone_exception_code IS NOT NULL AND uq_phone_exc;
    l_rows := :l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PUBLISH', 'COMPLETED',
        'C_S_TTF_PTY_RLE_PHN, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: good phones loaded, bad phones logged as Rejected Record exceptions. '
        || 'Count shown is total rows inserted across both inserts.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PUBLISH (total inserted)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TTF_Pty_Rle_Phn completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        -- Roll back the publish transaction if one is open (harmless if
        -- none is), then write the FAILED terminating row -- AFTER the
        -- rollback, so it is NOT rolled back.  Work tables are NOT
        -- dropped here: that is the whole point of KEPT.  The caller
        -- (workflow runner) will see the raise and stop the workflow;
        -- the operator restarts the mapping with a new run.
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_TTF_Pty_Rle_Phn failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
