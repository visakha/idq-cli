-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id  --  MODULAR REWRITE (simplified v2 style)
--
-- IDQ mapping: m_Tgt_C_S_TTF_Pty_Rle_Alt_Id, workflow wf_TTF_Stage_Load
-- (third mapping in the workflow run order, after Pty).
--
-- Business flow, in plain words: one alternate id per active TTF client
-- into C_S_TTF_PTY_RLE_ALT_ID -- the party key itself, type '024'.
-- Active means the party is not in the inactive-status table with a
-- status set (maintained by Pty_Validation, which runs first).  No
-- validation rule runs here.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement whose SELECT is a single query
--   (key subquery + already-loaded guard + QUALIFY dedup), one
--   transaction, one log line at the end.
--   This rewrite: the SAME business SQL, split at its natural
--   boundaries into named work tables, one step at a time.  No business
--   expression was changed; the publish is the original INSERT, written
--   against the final work table instead of the subquery, inside ONE
--   transaction.
--   FLAG -- THIN SPLIT: the original is a single short query, not a CTE
--   chain, so the split below is the closest sensible one: step 10
--   builds the candidate keys, step 20 applies the already-loaded guard
--   and the one-row-per-key dedup.  Step 20 is not a separate business
--   stage in the original; it is the guard + dedup half of the one
--   original SELECT, pulled out so the publish input can be counted
--   and inspected before it lands.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TTF_ALT_S1_KEYS   candidate keys: party key, submit
--                                  date, alternate-id key (party key +
--                                  '|Member|024|' + party key), active
--                                  clients only
--   Step 20  WRK_TTF_ALT_S2_DEDUP  keys not already loaded + one row
--                                  per key (latest submit date wins)
--   Step 30  PUBLISH               target, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_TTF_ALT_S1_KEYS, WRK_TTF_ALT_S2_DEDUP.
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
--     of C_S_TTF_PTY_RLE_ALT_ID is NOT performed; keys already in the
--     table are skipped instead.
--   * PRESERVED: the source read stores a SQL text that is only a WHERE
--     fragment (test client ids) and is not in custom-query mode, so it
--     is not applied -- no such filter appears in this rewrite either.
--   * PRESERVED: C_S_TTF_PTY_RLE_ALT_ID is unique on (PKEY_SRC_OBJECT,
--     VERSION_SEQ), which Snowflake does not enforce -- applied here by
--     the already-loaded guard plus the one-row-per-key dedup.
--   * PRESERVED: VERSION_SEQ = 1; PERIOD_START_DATE = run start (so it
--     changes on every run).
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty_Rle_Alt_Id';
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
    DROP TABLE IF EXISTS WRK_TTF_ALT_S1_KEYS;
    DROP TABLE IF EXISTS WRK_TTF_ALT_S2_DEDUP;

    -- ---- Step 10: CANDIDATE KEYS ----------------------------------------
    -- Purpose: one candidate row per active client -- the party key,
    -- the submit date, and the alternate-id key (party key + '|Member|
    -- 024|' + party key).  Inactive parties are filtered out here, using
    -- the inactive-status table maintained by Pty_Validation.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_ALT_S1_KEYS AS
    SELECT v.PTY_SRC_KEY, v.SUBMITDATE,
           NVL(v.PTY_SRC_KEY, '') || '|Member|024|' || NVL(v.PTY_SRC_KEY, '') AS pkey_src_object
      FROM V_TTF_ETL_SRC v
     -- Lkp_STG_TTF_PTY_INACTIVE_STS + Filter
     WHERE NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_ALT_S1_KEYS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'KEYS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_ALT_S1_KEYS', 'CREATED',
        'Candidate alternate-id keys for active clients only (inactive parties filtered out). '
        || 'Read by the dedup step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 KEYS', :l_rows) || CHR(10);

    -- ---- Step 20: GUARD + DEDUP -----------------------------------------
    -- Purpose: the publish-ready rows -- candidate keys that are not
    -- already in C_S_TTF_PTY_RLE_ALT_ID, reduced to one row per key
    -- (latest submit date wins).  This is the guard + dedup half of
    -- the original single SELECT, pulled out so the publish input can
    -- be counted and inspected before it lands.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_ALT_S2_DEDUP AS
    SELECT k.*
      FROM WRK_TTF_ALT_S1_KEYS k
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = k.pkey_src_object
     /* BAD DATA: unique key not yet in the table, first row per key in this run */
     WHERE xa.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object ORDER BY k.SUBMITDATE DESC NULLS LAST) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_ALT_S2_DEDUP;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DEDUP', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_ALT_S2_DEDUP', 'CREATED',
        'Publish-ready keys: not already loaded, one row per key (latest submit date wins). Published in step 30.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DEDUP', :l_rows) || CHR(10);

    -- ---- Step 30: PUBLISH -- one transaction, one target -----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction.  If the INSERT fails, the
    -- publish rolls back, the checkpoints for steps 10-20 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning.  The INSERT below is the original
    -- INSERT, with the same column list and values -- only the source
    -- changed, from the key subquery to step 20.
    BEGIN TRANSACTION;
    INSERT INTO C_S_TTF_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE, VERSION_SEQ, CREATE_DATE, PTY_RLE_FK,
            ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD, PERIOD_START_DATE, SRC_LAST_UPD_DT)
    SELECT k.pkey_src_object, 1, k.pkey_src_object, :l_run_ts, 1 /* TIMELINE: VERSION_SEQ */, k.SUBMITDATE,
           NVL(k.PTY_SRC_KEY, '') || '|Member', '024', k.PTY_SRC_KEY, '024', 'Issued',
           :l_run_ts /* TIMELINE: $sys.MappingRunStartTime */, k.SUBMITDATE
      FROM WRK_TTF_ALT_S2_DEDUP k;
    l_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'PUBLISH', 'COMPLETED',
        'C_S_TTF_PTY_RLE_ALT_ID',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: one alternate id (type 024) per active client. '
        || 'Count shown is rows inserted.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 PUBLISH (inserted)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TTF_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TTF_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
