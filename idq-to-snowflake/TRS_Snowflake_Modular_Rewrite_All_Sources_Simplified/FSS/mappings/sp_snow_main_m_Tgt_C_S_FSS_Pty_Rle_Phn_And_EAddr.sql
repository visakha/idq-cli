-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr, workflow
-- wf_FSS_Stage_Load.
--
-- What this mapping does, in plain words: each FSS registration row
-- (capture action not deleted, party not on the deactivation list) can
-- give one e-mail and one phone. E-mails are validated and loaded when
-- valid, logged when not. Phones are standardised and loaded when the
-- phone itself is valid; a bad phone is logged, and a bad extension is
-- logged separately while the phone still loads with the extension
-- blanked.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> dq ->
--   checked -> routed -> final), one transaction, one log line at the
--   end.  If it failed, nothing told you which logical stage had
--   finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   No step before publish writes to a final target, so the target
--   reads in later steps (keys already in the e-mail / phone tables)
--   still see the same target state as the original single statement
--   did.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_FSS_PHN_S1_SRC    source rows, deactivated parties
--                                  removed, e-mail / phone keys built
--   Step 20  WRK_FSS_PHN_S2_DQ     e-mail validation, phone
--                                  standardisation, extension check
--   Step 30  WRK_FSS_PHN_S3_CHECKED standardised e-mail, phone exception
--                                  code (area-code lookup), standardised
--                                  extension and its exception code
--   Step 40  WRK_FSS_PHN_S4_ROUTED exception details, good / bad groups
--                                  for e-mail, phone and extension,
--                                  insert-only guards
--   Step 50  PUBLISH               targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_FSS_PHN_S1_SRC, WRK_FSS_PHN_S2_DQ, WRK_FSS_PHN_S3_CHECKED,
--   WRK_FSS_PHN_S4_ROUTED.  They live in the same schema as the targets
--   (unqualified names, as in the original code), are prefixed
--   WRK_FSS_, and are registered in the shared job-control table at
--   creation.  They survive a session crash (TRANSIENT, not TEMP),
--   which is what makes inspection after a run possible.  A Snowflake
--   CURSOR was NOT used: cursors process row by row, and every step
--   here is set-based by design -- the work table IS the result set,
--   held as a table instead of in memory, so it can be counted and
--   inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  The IDQ truncate of the e-mail and phone
--     tables is NOT performed; keys already present are skipped
--     instead (uq_eaddr / uq_phn guards).  A re-run therefore inserts
--     nothing twice, but it also does not remove rows that IDQ would
--     have truncated away.
--   * PRESERVED: a row with a good phone and a bad extension is loaded
--     (extension blanked) AND logged as a bad-value exception.
--   * PRESERVED: an e-mail whose validation code is not configured in
--     the exception catalogue is loaded (the bad group needs a
--     looked-up code, so an unconfigured code falls in the good
--     group).
--   * PRESERVED: the phone area-code lookup reads the shared phone
--     area-code reference through fn_snow_helper44_common, exactly as
--     in the original.
--   * Version sequence is '1' on both targets and the period start
--     date is the last-update date, exactly as in the original.
--
-- INSTALL
--   Install schema is FSS_ETL_WRK in database MDM_ETL_FSS.  All table
--   names in the code below are unqualified, as in the original code.
--   Shared control calls (sp_etl_job_begin / sp_etl_checkpoint /
--   sp_etl_job_finish / sp_etl_job_fail) take SOURCE first and live in
--   the shared framework; shared helpers are fn_snow_helperNN_common.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order (this
--   mapping had none), so every existing CALL still works.  One
--   parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'FSS';
    c_workflow   VARCHAR DEFAULT 'wf_FSS_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr';
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
            'FSS_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_FSS_PHN_S1_SRC;
    DROP TABLE IF EXISTS WRK_FSS_PHN_S2_DQ;
    DROP TABLE IF EXISTS WRK_FSS_PHN_S3_CHECKED;
    DROP TABLE IF EXISTS WRK_FSS_PHN_S4_ROUTED;

    -- ---- Step 10: SOURCE + REMOVE DEACTIVATED ------------------------------
    -- Purpose: the registration rows to process -- capture action not
    -- deleted, party not on the deactivation list -- with the role,
    -- e-mail and phone keys built.  Every later step reads this table,
    -- never the raw source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PHN_S1_SRC AS
    SELECT v.PTY_SRC_KEY, v.ADDR_EMAIL, v.NBR_PHONE, v.NBR_PHONE_EXT, v.SOURCE_TYPE, v.ID_REGISTRATION_CLIENT,
           v.DT_LAST_UPDATE,
           NVL(v.PTY_SRC_KEY, '') || '|Member'                                             AS pty_rle_fk,
           NVL(v.PTY_SRC_KEY, '') || '|Member|001|' || NVL(LPAD(TO_VARCHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '')
           || '|' || NVL(TRIM(v.ADDR_EMAIL), '')                                           AS eaddr_pkey,
           NVL(v.PTY_SRC_KEY, '') || '|Member|Telephone|001|'
           || NVL(LPAD(TO_VARCHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '') || '|' || NVL(TRIM(v.NBR_PHONE), '')
                                                                                           AS phn_pkey
      FROM V_FSS_ETL_SRC v
     WHERE v.DTL__CAPXACTION <> 'D'
       AND NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PHN_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PHN_S1_SRC', 'CREATED',
        'Source registration rows with role, e-mail and phone keys built, deactivated parties removed. '
        || 'Read by the validation step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: VALIDATE + STANDARDISE -----------------------------------
    -- Purpose: validate the e-mail, standardise the phone and check
    -- the extension, for rows that have an e-mail / phone.  Reads ONLY
    -- WRK_FSS_PHN_S1_SRC.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PHN_S2_DQ AS
    SELECT s.*,
           IFF(s.ADDR_EMAIL IS NOT NULL, fn_snow_helper22_common(s.ADDR_EMAIL), NULL)    AS em,
           IFF(s.NBR_PHONE IS NOT NULL, fn_snow_helper23_common(s.NBR_PHONE), NULL)      AS std_phone,
           IFF(s.NBR_PHONE IS NOT NULL, fn_snow_helper25_common(s.NBR_PHONE_EXT), NULL)  AS px
      FROM WRK_FSS_PHN_S1_SRC s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PHN_S2_DQ;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DQ_VALIDATE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PHN_S2_DQ', 'CREATED',
        'E-mail validation, phone standardisation and extension check results attached. '
        || 'Read by the area-code check step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DQ_VALIDATE', :l_rows) || CHR(10);

    -- ---- Step 30: AREA-CODE CHECK ---------------------------------------------
    -- Purpose: flatten the standardised e-mail and extension, and
    -- derive the phone exception code from the standardised phone and
    -- its area-code reference row.  Reads ONLY WRK_FSS_PHN_S2_DQ.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PHN_S3_CHECKED AS
    WITH
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common()))
    SELECT d.*,
           d.em:email_address::VARCHAR                                                   AS std_email,
           /* VALIDATION */
           IFF(d.NBR_PHONE IS NOT NULL,
               fn_snow_helper24_common(d.std_phone, 'FSS', '001', ar.NPA_ID, ar.SERVICE), NULL) AS phone_exception_code,
           d.px:phone_nbr_ext::VARCHAR                                                   AS std_ext,
           d.px:exception_code::VARCHAR                                                  AS ext_exception_code
      FROM WRK_FSS_PHN_S2_DQ d
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.std_phone, 1, 3);
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PHN_S3_CHECKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'CHECKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PHN_S3_CHECKED', 'CREATED',
        'Standardised e-mail, phone exception code from the area-code reference, standardised extension and its exception code. '
        || 'Read by the router step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 CHECKED', :l_rows) || CHR(10);

    -- ---- Step 40: ROUTE --------------------------------------------------------
    -- Purpose: resolve the exception descriptions, put every row into
    -- its good / bad groups for e-mail, phone and extension, blank the
    -- extension on the loaded phone when the extension is bad, and set
    -- the insert-only guards.  This is the only table step 50 reads.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PHN_S4_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    routed AS (
        SELECT c.*,
               xe.EXCEPTION_CODE  AS email_exception_code,
               xe.EXCEPTION_DESC  AS email_exception_desc,
               xe.EXCEPTION_TYPE  AS email_exception_type,
               xp.EXCEPTION_DESC  AS phone_exception_desc,
               xx.EXCEPTION_DESC  AS ext_exception_desc,
               (c.ADDR_EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NULL)          AS grp_email_good,
               (c.ADDR_EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NOT NULL)      AS grp_email_bad,
               (c.NBR_PHONE IS NOT NULL AND c.phone_exception_code IS NULL)      AS grp_phone_good,
               (c.NBR_PHONE IS NOT NULL AND c.phone_exception_code IS NOT NULL)  AS grp_phone_bad,
               (c.NBR_PHONE IS NOT NULL AND c.ext_exception_code IS NOT NULL)    AS grp_ext_bad
          FROM WRK_FSS_PHN_S3_CHECKED c
          LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = c.em:exception_code::VARCHAR
          LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
          LEFT JOIN lkp_exc xx ON xx.EXCEPTION_CODE = c.ext_exception_code
    )
    SELECT r.*,
           '1' /* TIMELINE: VERSION_SEQ */                          AS version_seq,
           1                                                         AS hub_state_ind,
           'FSS'                                                     AS src_sys,
           :l_run_ts                                                 AS run_ts,
           :c_mapping                                                AS mapping_name,
           '001'                                                     AS eaddr_addr_tp,
           'Active'                                                  AS eaddr_sts_cd,
           'Y'                                                       AS eaddr_is_vld,
           'Telephone'                                               AS phn_tp,
           '001'                                                     AS usg_tp,
           'Primary'                                                 AS pref_lvl,
           /* BAD DATA: an invalid extension is blanked on the loaded phone */
           IFF(r.ext_exception_code IS NULL, r.std_ext, NULL)        AS phn_num_ext,
           'Email'                                                   AS attr_email,
           'Main Phone'                                              AS attr_phone,
           'Main Phone Ext'                                          AS attr_phone_ext,
           'Rejected Record'                                         AS exc_type_rejected,
           'Bad Value'                                               AS exc_type_bad_value,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.eaddr_pkey
                                   ORDER BY r.DT_LAST_UPDATE DESC, r.ID_REGISTRATION_CLIENT) = 1
            AND xea.PKEY_SRC_OBJECT IS NULL)                         AS uq_eaddr,
           (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.phn_pkey
                                   ORDER BY r.DT_LAST_UPDATE DESC, r.ID_REGISTRATION_CLIENT) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL)                         AS uq_phn,
           ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                           r.email_exception_type, r.email_exception_code
                                  ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_email_exc,
           ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                           r.phone_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_phone_exc,
           ROW_NUMBER() OVER (PARTITION BY r.grp_ext_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                           r.ext_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1   AS uq_ext_exc
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
             ON xea.PKEY_SRC_OBJECT = r.eaddr_pkey
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = r.phn_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PHN_S4_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PHN_S4_ROUTED', 'CREATED',
        'Routed rows: good / bad groups for e-mail, phone and extension, with insert-only guards. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The five INSERTs below are the five branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final CTE to step 40.  A row can land in more
    -- than one branch (a loaded phone AND its extension exception),
    -- exactly as in INSERT ALL.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 50a. Valid e-mails -> C_S_FSS_PTY_RLE_EADDR
    INSERT INTO C_S_FSS_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, ADDR_TP, USG_TP, ELEC_ADDR, STS_CD, IS_VLD, SRC_LAST_UPD_DT)
    SELECT eaddr_pkey, DT_LAST_UPDATE, version_seq, run_ts, run_ts, eaddr_pkey, hub_state_ind, pty_rle_fk,
           eaddr_addr_tp, NULL, std_email, eaddr_sts_cd, eaddr_is_vld, DT_LAST_UPDATE
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_email_good AND uq_eaddr;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50b. Bad e-mails -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
            PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
    SELECT src_sys, email_exception_code, email_exception_desc, run_ts, ADDR_EMAIL, mapping_name,
           email_exception_type, DT_LAST_UPDATE, ADDR_EMAIL, attr_email, PTY_SRC_KEY, ID_REGISTRATION_CLIENT
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_email_bad AND uq_email_exc;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50c. Good phones -> C_S_FSS_PTY_RLE_PHN
    INSERT INTO C_S_FSS_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
            PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, PHN_NUM_EXT)
    SELECT phn_pkey, DT_LAST_UPDATE, version_seq, run_ts, phn_pkey, hub_state_ind, pty_rle_fk, phn_tp,
           usg_tp, std_phone, pref_lvl, DT_LAST_UPDATE, phn_num_ext
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_phone_good AND uq_phn;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50d. Bad phones -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
            SRC_SYS_ID_2)
    SELECT src_sys, phone_exception_code, phone_exception_desc, run_ts, NBR_PHONE, NULL, NULL,
           mapping_name, PTY_SRC_KEY, exc_type_rejected, DT_LAST_UPDATE, NBR_PHONE, attr_phone,
           ID_REGISTRATION_CLIENT
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_phone_bad AND uq_phone_exc;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50e. Bad extensions -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            PRIMARY_PHONE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, PERIOD_START_DATE, MAPPING_NAME)
    SELECT src_sys, PTY_SRC_KEY, ID_REGISTRATION_CLIENT, exc_type_bad_value, ext_exception_code,
           ext_exception_desc, run_ts, NBR_PHONE_EXT, NBR_PHONE_EXT, attr_phone_ext, DT_LAST_UPDATE,
           mapping_name
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_ext_bad AND uq_ext_exc;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_FSS_PTY_RLE_EADDR, C_S_FSS_PTY_RLE_PHN, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid e-mails, valid phones and e-mail / phone / extension exceptions. '
        || 'Count shown is the total rows inserted by all five INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
