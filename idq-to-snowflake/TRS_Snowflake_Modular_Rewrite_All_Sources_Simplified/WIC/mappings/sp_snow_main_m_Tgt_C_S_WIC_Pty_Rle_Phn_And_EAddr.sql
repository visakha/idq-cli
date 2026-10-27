-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr  --  MODULAR REWRITE
--
-- Original: IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr, workflow
-- wf_WIC_Stage_Load. Original Snowflake procedure
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.
--
-- What this mapping does, in plain words: each active WIC row gives
-- one phone and possibly one e-mail. The phone is standardised and
-- validated on every active row: good phones load into the phone
-- table, bad phones are logged as exceptions. A non-null e-mail is
-- validated the same way: valid e-mails load into the e-mail table,
-- bad e-mails are logged as exceptions.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> checked
--   -> routed -> final SELECT), one transaction, one log line at the
--   end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_WIC_PHN_S10_SRC     active source rows + phone / e-mail
--                                   keys + standardised phone and the
--                                   e-mail validation object
--   Step 20  WRK_WIC_PHN_S20_CHECKED phone exception code (area-code
--                                   lookup) + standardised e-mail
--   Step 30  WRK_WIC_PHN_S30_ROUTED  exception descriptions / codes /
--                                   types resolved + good / bad routing
--                                   groups for phones and e-mails
--   Step 40  WRK_WIC_PHN_S40_READY   run constants + the insert-only
--                                   guards (uq_phn, uq_eaddr,
--                                   uq_phone_exc, uq_email_exc)
--   Step 50  PUBLISH                targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_WIC_PHN_S10_SRC, WRK_WIC_PHN_S20_CHECKED,
--   WRK_WIC_PHN_S30_ROUTED, WRK_WIC_PHN_S40_READY. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code), are prefixed WRK_WIC_, and are registered in JOB_CONTROL_ETL
--   at creation. They survive a session crash (TRANSIENT, not TEMP),
--   which is what makes inspection after a run possible. A Snowflake
--   CURSOR was NOT used: cursors process row by row, and every step
--   here is set-based by design -- the work table IS the result set,
--   held as a table instead of in memory, so it can be counted and
--   inspected after the run.
--
-- INSTALL LOCATION
--   Install schema is WIC_ETL_WRK in database MDM_ETL_WIC. All table
--   names in the code below are unqualified, exactly as in the original.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ truncate of C_S_WIC_PTY_RLE_PHN and
--     C_S_WIC_PTY_RLE_EADDR is NOT performed; instead keys already
--     present are skipped (uq_phn / uq_eaddr guards).
--   * PRESERVED: there is no null-phone filter -- a party without a
--     phone is validated and logged as an invalid phone, exactly as
--     in the original.
--   * PRESERVED: the e-mail key uses the e-mail as read (no trim),
--     unlike the equivalent ECI mapping.
--   * PRESERVED: the phone routing groups overlap by construction --
--     a 'Missing_AreaCode' code counts as both a good phone (no code,
--     or 'Missing_AreaCode') and a bad phone (any code), so the
--     original INSERT ALL would write such a row to both the phone
--     table and the exception table. The publish INSERTs below keep
--     the same WHEN conditions, so the overlap is preserved. The
--     original header notes 'Missing_AreaCode' only exists for ECI,
--     so WIC never gets it in practice.
--   * PRESERVED: VERSION_SEQ is '1' on both targets and
--     PERIOD_START_DATE = DATEKEY.
--   * PRESERVED: the insert-only guards (uq_*) are evaluated in step
--     40, before the publish transaction, against the targets as they
--     stand at that point -- the same snapshot behaviour as the
--     original single INSERT ALL, whose source query was evaluated
--     once before any branch inserted.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order (this
--   mapping has none), so every existing CALL still works. One
--   parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'WIC';
    c_workflow   VARCHAR DEFAULT 'wf_WIC_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr';
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
            'WIC_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_WIC_PHN_S10_SRC;
    DROP TABLE IF EXISTS WRK_WIC_PHN_S20_CHECKED;
    DROP TABLE IF EXISTS WRK_WIC_PHN_S30_ROUTED;
    DROP TABLE IF EXISTS WRK_WIC_PHN_S40_READY;

    -- ---- Step 10: SRC -- active rows + keys + standardised phone / e-mail object
    -- Purpose: active source rows only (the deactivation-status
    -- filter), each with its party-role key, phone key and e-mail key,
    -- its standardised phone, and its e-mail validation object (NULL
    -- when the e-mail is null). This is the only step that reads
    -- V_WIC_ETL_SRC; every later step reads work tables.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PHN_S10_SRC AS
    SELECT v.SOURCE_TABLE, v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.FID, v.PHONE, v.EMAIL,
           NVL(v.PTY_SRC_KEY, '') || '|Member'                                            AS pty_rle_fk,
           NVL(v.PTY_SRC_KEY, '') || '|Member|Telephone|001|' || NVL(TO_VARCHAR(v.FID), '') || '|'
           || NVL(TRIM(v.PHONE), '')                                                      AS phn_pkey,
           NVL(v.PTY_SRC_KEY, '') || '|Member|001|' || NVL(TO_VARCHAR(v.FID), '') || '|' || NVL(v.EMAIL, '')
                                                                                          AS eaddr_pkey,
           fn_snow_helper23_common(v.PHONE)                                               AS std_phone,
           IFF(v.EMAIL IS NOT NULL, fn_snow_helper22_common(v.EMAIL), NULL)               AS em
      FROM V_WIC_ETL_SRC v
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PHN_S10_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PHN_S10_SRC', 'CREATED',
        'Active source rows only, with party-role / phone / e-mail keys, the standardised phone, and the '
        || 'e-mail validation object. Read by the validation step; the source view is not re-read after '
        || 'this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC', :l_rows) || CHR(10);

    -- ---- Step 20: CHECKED -- phone exception code + standardised e-mail -
    -- Purpose: validate the standardised phone against the area-code
    -- lookup (usage '001') to get its exception code, and pull the
    -- standardised e-mail out of the e-mail validation object. Reads
    -- ONLY step 10 (plus the area-code lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PHN_S20_CHECKED AS
    WITH
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common()))
    SELECT s.*,
           /* VALIDATION */ fn_snow_helper24_common(s.std_phone, 'WIC', '001', ar.NPA_ID, ar.SERVICE) AS phone_exception_code,
           s.em:email_address::VARCHAR                                                   AS std_email
      FROM WRK_WIC_PHN_S10_SRC s
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(s.std_phone, 1, 3);
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PHN_S20_CHECKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'CHECKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PHN_S20_CHECKED', 'CREATED',
        'Phone exception code from the area-code lookup, and the standardised e-mail pulled out. '
        || 'Read by the routing step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 CHECKED', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTED -- resolved exceptions + good / bad groups -----
    -- Purpose: resolve the phone and e-mail exception descriptions /
    -- codes / types from the exception lookup, and split every row
    -- into its phone and e-mail routing groups: good phones (no code,
    -- or 'Missing_AreaCode'), bad phones (any code), good e-mails
    -- (non-null e-mail, no exception code) and bad e-mails (non-null
    -- e-mail, exception code). Reads ONLY step 20 (plus the lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PHN_S30_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT c.*,
           xp.EXCEPTION_DESC AS phone_exception_desc,
           xe.EXCEPTION_CODE AS email_exception_code,
           xe.EXCEPTION_DESC AS email_exception_desc,
           xe.EXCEPTION_TYPE AS email_exception_type,
           (c.phone_exception_code IS NULL OR c.phone_exception_code = 'Missing_AreaCode') AS grp_phone_good,
           c.phone_exception_code IS NOT NULL                                            AS grp_phone_bad,
           (c.EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NULL)                            AS grp_email_good,
           (c.EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NOT NULL)                        AS grp_email_bad
      FROM WRK_WIC_PHN_S20_CHECKED c
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = c.em:exception_code::VARCHAR;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PHN_S30_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PHN_S30_ROUTED', 'CREATED',
        'Resolved phone / e-mail exception details, with good / bad routing groups for phones and e-mails. '
        || 'Read by the guard step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 40: READY -- run constants + insert-only guards ------------
    -- Purpose: the rows that publish will write. Run constants are
    -- attached (phone type 'Telephone', usage '001', preference
    -- 'Primary', e-mail type '001', status 'Active', valid 'Y'), and
    -- the insert-only guards are computed: first row per good phone /
    -- e-mail key not already in the target, and first row per bad
    -- phone / e-mail exception key.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PHN_S40_READY AS
    SELECT r.*,
           '1' /* TIMELINE: VERSION_SEQ */                          AS version_seq,
           1                                                         AS hub_state_ind,
           'WIC'                                                     AS src_sys,
           :l_run_ts                                                 AS run_ts,
           :c_mapping                                                AS mapping_name,
           'Telephone'                                               AS phn_tp,
           '001'                                                     AS usg_tp,
           'Primary'                                                 AS pref_lvl,
           'Bad Value'                                               AS exc_type_bad_value,
           'Main Phone'                                              AS attr_phone,
           'Email'                                                   AS attr_email,
           '001'                                                     AS eaddr_addr_tp,
           'Active'                                                  AS eaddr_sts_cd,
           'Y'                                                       AS eaddr_is_vld,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.phn_pkey ORDER BY r.DATEKEY DESC, r.FID) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL)                         AS uq_phn,
           (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.eaddr_pkey ORDER BY r.DATEKEY DESC, r.FID) = 1
            AND xea.PKEY_SRC_OBJECT IS NULL)                         AS uq_eaddr,
           ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.PTY_SRC_KEY, r.FID, r.phone_exception_code
                                  ORDER BY r.DATEKEY DESC) = 1       AS uq_phone_exc,
           ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.PTY_SRC_KEY, r.FID, r.email_exception_type,
                                           r.email_exception_code ORDER BY r.DATEKEY DESC) = 1 AS uq_email_exc
      FROM WRK_WIC_PHN_S30_ROUTED r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = r.phn_pkey
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
             ON xea.PKEY_SRC_OBJECT = r.eaddr_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PHN_S40_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'READY', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PHN_S40_READY', 'CREATED',
        'Ready rows: run constants attached, and insert-only guards (uq_phn, uq_eaddr, uq_phone_exc, '
        || 'uq_email_exc). Read by the publish step; the target guards are evaluated here, before publish, '
        || 'as in the original single query.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 READY', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning. The four INSERTs below are the
    -- four branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHEN conditions -- only the
    -- source changed, from the original query to step 40.
    BEGIN TRANSACTION;
    -- 50a. Good phones -> C_S_WIC_PTY_RLE_PHN
    INSERT INTO C_S_WIC_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, PTY_RLE_FK, PHN_TP,
            USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, HUB_STATE_IND)
    SELECT phn_pkey, DATEKEY, version_seq, run_ts, phn_pkey, pty_rle_fk, phn_tp, usg_tp, std_phone, pref_lvl,
           DATEKEY, hub_state_ind
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_phone_good AND uq_phn;
    -- 50b. Bad phones -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, SRC_SYS_ID_2)
    SELECT src_sys, phone_exception_code, phone_exception_desc, run_ts, std_phone, NULL, NULL, mapping_name,
           PTY_SRC_KEY, exc_type_bad_value, usg_tp, DATEKEY, std_phone, attr_phone, FID
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_phone_bad AND uq_phone_exc;
    -- 50c. Valid e-mails -> C_S_WIC_PTY_RLE_EADDR
    INSERT INTO C_S_WIC_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, ADDR_TP)
    SELECT eaddr_pkey, DATEKEY, version_seq, run_ts, run_ts, eaddr_pkey, hub_state_ind, pty_rle_fk,
           std_email, NULL, eaddr_sts_cd, eaddr_is_vld, DATEKEY, eaddr_addr_tp
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_email_good AND uq_eaddr;
    -- 50d. Bad e-mails -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
            PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
    SELECT src_sys, email_exception_code, email_exception_desc, run_ts, EMAIL, mapping_name,
           email_exception_type, DATEKEY, EMAIL, attr_email, PTY_SRC_KEY, FID
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_email_bad AND uq_email_exc;
    COMMIT;
    -- Publish row counts by branch are not summed here; report the
    -- ready-row count that fed the publish instead.
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PHN_S40_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_WIC_PTY_RLE_PHN, C_S_WIC_PTY_RLE_EADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: good phones, bad-phone exceptions, valid e-mails, and bad-e-mail '
        || 'exceptions. Count shown is ready rows feeding the publish; each branch inserts only its own '
        || 'WHEN-filtered subset.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (ready rows)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        -- Roll back the publish transaction if one is open (harmless if
        -- none is), then write the FAILED terminating row -- AFTER the
        -- rollback, so it is NOT rolled back. Work tables are NOT
        -- dropped here: that is the whole point of KEPT. The caller
        -- (workflow runner) will see the raise and stop the workflow;
        -- the operator restarts the mapping with a new run.
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
