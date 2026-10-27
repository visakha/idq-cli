-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads alternate ids of the ECI parties into the role alternate-id
--   table: child ECI id (018), child SSN (004, only when valid),
--   Medicaid number (002, only when valid, via the case table) and
--   family ECI id (019). Invalid SSNs and Medicaid ids are not loaded,
--   only logged. The id written is the SOURCE value; the standardised
--   SSN / Medicaid id is only used for validation.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> active
--   -> dq -> routed -> final SELECT), one transaction, one log line.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_ALT_S10_SRC      four alternate-id branches
--                                     (018, 004, 002, 019)
--   Step 20  WRK_ECI_ALT_S20_ACTIVE   ids whose party is not
--                                     deactivated
--   Step 30  WRK_ECI_ALT_S30_ROUTED   SSN / Medicaid validation and
--                                     router groups (valid, SSN
--                                     exception, Medicaid exception)
--   Step 40  WRK_ECI_ALT_S40_READY    publish-ready rows with
--                                     insert-only guards
--   Step 50  PUBLISH                targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_ALT_S10_SRC, WRK_ECI_ALT_S20_ACTIVE,
--   WRK_ECI_ALT_S30_ROUTED, WRK_ECI_ALT_S40_READY. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Keys already present are skipped (uq_alt_id
--     guard).
--   * The SSN exception row has no RUN_DATE linked (NULL) and writes
--     the exception code returned by the exception lookup (NULL when
--     Invalid_SSN is not configured); the Medicaid exception row
--     writes the computed code; preserved. Because the SSN row's
--     RUN_DATE is NULL, its key repeats from run to run: in Oracle the
--     unique constraint rejects the row of every later run, so an
--     invalid SSN is logged only once, ever. That is reproduced here
--     (key already in the table -> skipped, via the uq_ssn_exc guard).
--   * VERSION_SEQ is 1; PERIOD_START_DATE is source DATE_CREATED;
--     preserved.
--
-- SIGNATURE
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'ECI';
    c_workflow   VARCHAR DEFAULT 'wf_ECI_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_run_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_pub_rows   NUMBER DEFAULT 0;
    l_summary    VARCHAR DEFAULT '';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(:P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin('ECI', :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    DROP TABLE IF EXISTS WRK_ECI_ALT_S10_SRC;
    DROP TABLE IF EXISTS WRK_ECI_ALT_S20_ACTIVE;
    DROP TABLE IF EXISTS WRK_ECI_ALT_S30_ROUTED;
    DROP TABLE IF EXISTS WRK_ECI_ALT_S40_READY;

    -- ---- Step 10: ALTERNATE-ID BRANCHES ----------------------------------
    -- Purpose: one row per alternate id -- child ECI id 018, child SSN
    -- 004 (only when present), Medicaid number 002 (via the case
    -- table), family ECI id 019. This is the original src CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ALT_S10_SRC AS
    SELECT ID_CHILD AS ID, LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member' AS PTY_REL_FK,
           LPAD(TO_VARCHAR(ID_CHILD), 10, '0') AS SRC_KEY_SFX, '018' AS ALT_ID_TP,
           LPAD(TO_VARCHAR(ID_CHILD), 10, '0') AS ALT_ID_VAL, DATE_CREATED, DATE_MODIFIED,
           LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member' || '|018' || '|'
           || LPAD(TO_VARCHAR(ID_CHILD), 10, '0') AS PKEY_SRC_OBJECT
      FROM STG_ECI_D_CHILD
    UNION ALL
    SELECT ID_CHILD, LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member', LPAD(TO_VARCHAR(ID_CHILD), 10, '0'),
           '004', CHILD_SSN, DATE_CREATED, DATE_MODIFIED,
           LPAD(TO_VARCHAR(ID_CHILD), 10, '0') || '|Member' || '|004' || '|' || LPAD(TO_VARCHAR(ID_CHILD), 10, '0')
      FROM STG_ECI_D_CHILD
     WHERE CHILD_SSN IS NOT NULL
    UNION ALL
    SELECT C.ID_CHILD, LPAD(TO_VARCHAR(C.ID_CHILD), 10, '0') || '|Member', LPAD(TO_VARCHAR(M.ID_MEDICAID), 9, '0'),
           '002', M.MEDICAID_NBR, M.DATE_CREATED, M.DATE_MODIFIED,
           LPAD(TO_VARCHAR(C.ID_CHILD), 10, '0') || '|Member' || '|002' || '|' || LPAD(TO_VARCHAR(M.ID_MEDICAID), 10, '0')
      FROM STG_ECI_D_MEDICAID M
     INNER JOIN STG_ECI_SN_CASE C ON M.ID_CASE = C.ID_CASE
    UNION ALL
    SELECT ID_FAMILY, LPAD(TO_VARCHAR(ID_FAMILY), 10, '0') || 'F|Member', LPAD(TO_VARCHAR(ID_FAMILY), 10, '0'),
           '019', LPAD(TO_VARCHAR(ID_FAMILY), 10, '0'), DATE_CREATED, DATE_MODIFIED,
           LPAD(TO_VARCHAR(ID_FAMILY), 10, '0') || 'F|Member' || '|019' || '|' || LPAD(TO_VARCHAR(ID_FAMILY), 10, '0')
      FROM STG_ECI_D_FAMILY;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ALT_S10_SRC;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_ALT_IDS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ALT_S10_SRC', 'CREATED',
        'Alternate-id branches: child ECI id, child SSN, Medicaid number and family ECI id. '
        || 'Read by the active filter.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_ALT_IDS', :l_rows) || CHR(10);

    -- ---- Step 20: ACTIVE PARTIES ONLY ------------------------------------
    -- Purpose: drop ids whose party (first 11 characters of the role
    -- key, '|' trimmed) has a deactivation status. This is the
    -- original active CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ALT_S20_ACTIVE AS
    SELECT s.*
      FROM WRK_ECI_ALT_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = RTRIM(SUBSTR(s.PTY_REL_FK, 1, 11), '|') AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ALT_S20_ACTIVE;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'ACTIVE_ALT_IDS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ALT_S20_ACTIVE', 'CREATED',
        'Alternate ids of active parties only. Read by the validation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 ACTIVE_ALT_IDS', :l_rows) || CHR(10);

    -- ---- Step 30: VALIDATION + ROUTING -----------------------------------
    -- Purpose: validate SSNs and Medicaid ids and sort rows into the
    -- valid group, the SSN-exception group and the Medicaid-exception
    -- group, with exception descriptions resolved. Reads ONLY step 20.
    -- This is the original dq + routed CTEs.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ALT_S30_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    dq AS (
        SELECT a.*,
               IFF(a.ALT_ID_TP = '004' AND fn_snow_helper26_common(a.ALT_ID_VAL):ssn_status::VARCHAR = 'Invalid',
                   'Invalid_SSN', NULL)                                                    AS ssn_exception_code,
               IFF(a.ALT_ID_TP = '002', fn_snow_helper27_common(a.ALT_ID_VAL):exception_code::VARCHAR, NULL)
                                                                                           AS medicaid_exception_code
          FROM WRK_ECI_ALT_S20_ACTIVE a
    )
    SELECT d.*,
           xs.EXCEPTION_CODE AS ssn_lkp_code, xs.EXCEPTION_DESC AS ssn_lkp_desc, xs.EXCEPTION_TYPE AS ssn_lkp_type,
           xm.EXCEPTION_TYPE AS medicaid_exception_type, xm.EXCEPTION_DESC AS medicaid_exception_desc,
           ((d.ALT_ID_TP = '004' AND d.ssn_exception_code IS NULL)
            OR d.ALT_ID_TP IN ('018', '019')
            OR (d.ALT_ID_TP = '002' AND d.medicaid_exception_code IS NULL))          AS grp_valid,
           (d.ALT_ID_TP = '004' AND d.ssn_exception_code IS NOT NULL)                 AS grp_ssn_exc,
           (d.ALT_ID_TP = '002' AND d.medicaid_exception_code IS NOT NULL)            AS grp_mcd_exc
      FROM dq d
      LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.ssn_exception_code
      LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = d.medicaid_exception_code;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ALT_S30_ROUTED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'VALIDATED_ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ALT_S30_ROUTED', 'CREATED',
        'Validated alternate ids sorted into valid, SSN-exception and Medicaid-exception groups. '
        || 'Read by the ready step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 VALIDATED_ROUTED', :l_rows) || CHR(10);

    -- ---- Step 40: READY -- guards -----------------------------------------
    -- Purpose: the publish-ready rows with the insert-only guards
    -- (key not yet in the target, first row per key in this run; for
    -- SSN exceptions, key not already logged with a NULL run date).
    -- Reads ONLY step 30. This is the original final SELECT (including
    -- the target-table guard joins, which still see the pre-run state
    -- because nothing has been published yet).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ALT_S40_READY AS
    SELECT r.*,
           TO_VARCHAR(r.ID) || '|' || r.ALT_ID_TP                    AS src_rowid,
           1 /* TIMELINE: VERSION_SEQ */                             AS version_seq,
           'Issued'                                                  AS sts_cd,
           1                                                         AS hub_state_ind,
           NVL(r.DATE_MODIFIED, r.DATE_CREATED)                      AS src_last_upd_dt,
           'ECI'                                                     AS src_sys,
           :l_run_ts                                                 AS run_ts,
           :c_mapping                                                AS mapping_name,
           'ALT_ID_Type_SSN'                                         AS attr_ssn,
           'ALT_ID_TP_MedicaidId'                                    AS attr_medicaid,
           (ROW_NUMBER() OVER (PARTITION BY r.grp_valid, r.PKEY_SRC_OBJECT ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                          AS uq_alt_id,
           (ROW_NUMBER() OVER (PARTITION BY r.grp_ssn_exc, r.PKEY_SRC_OBJECT, r.PTY_REL_FK, r.ssn_lkp_type,
                                            r.ssn_lkp_code ORDER BY r.ID) = 1
            AND xe.SRC_SYS_ID_1 IS NULL)                             AS uq_ssn_exc,
           ROW_NUMBER() OVER (PARTITION BY r.grp_mcd_exc, r.PKEY_SRC_OBJECT, r.PTY_REL_FK,
                                           r.medicaid_exception_type, r.medicaid_exception_code
                                  ORDER BY r.ID) = 1                 AS uq_mcd_exc
      FROM WRK_ECI_ALT_S30_ROUTED r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = r.PKEY_SRC_OBJECT
      LEFT JOIN (SELECT DISTINCT SRC_SYS_ID_1, SRC_SYS_ID_2, NVL(EXCEPTION_TYPE, '~') AS EXC_TYPE,
                        NVL(EXCEPTION_CODE, '~') AS EXC_CODE
                   FROM EXC_STG_BAD_REC_MEMB
                  WHERE SRC_SYS = 'ECI' AND RUN_DATE IS NULL AND SRC_SYS_ID_3 IS NULL) xe
             ON r.grp_ssn_exc AND xe.SRC_SYS_ID_1 = r.PKEY_SRC_OBJECT AND xe.SRC_SYS_ID_2 = r.PTY_REL_FK
            AND xe.EXC_TYPE = NVL(r.ssn_lkp_type, '~') AND xe.EXC_CODE = NVL(r.ssn_lkp_code, '~');
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ALT_S40_READY;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'READY_TO_PUBLISH', 'COMPLETED', 'C_S_ECI_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_ECI_ALT_S40_READY', 'CREATED',
        'Publish-ready alternate ids with insert-only guards (uq_alt_id, uq_ssn_exc, uq_mcd_exc). '
        || 'Published in step 50.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The three INSERTs below are
    -- the three branches of the original INSERT ALL, in the same order,
    -- with the same column lists, values and WHERE conditions -- only
    -- the source changed, from the final SELECT to step 40. No
    -- TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    -- 50a. Valid alternate ids -> C_S_ECI_PTY_RLE_ALT_ID
    INSERT INTO C_S_ECI_PTY_RLE_ALT_ID
           (PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE, PKEY_SRC_OBJECT, SRC_ROWID,
            VERSION_SEQ, STS_CD, HUB_STATE_IND, SRC_LAST_UPD_DT, ALT_ID_TP_FLTR, PERIOD_START_DATE)
    SELECT PTY_REL_FK, ALT_ID_TP, ALT_ID_VAL, DATE_CREATED, run_ts, PKEY_SRC_OBJECT, src_rowid,
           version_seq, sts_cd, hub_state_ind, src_last_upd_dt, ALT_ID_TP, DATE_CREATED
      FROM WRK_ECI_ALT_S40_READY
     WHERE grp_valid AND uq_alt_id;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 50b. Invalid SSN -> EXC_STG_BAD_REC_MEMB (RUN_DATE unlinked, NULL)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, SRC_SYS, ATTRIBUTE_NAME, MAPPING_NAME,
            ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2)
    SELECT ssn_lkp_code, ssn_lkp_desc, ssn_lkp_type, src_sys, attr_ssn, mapping_name, ALT_ID_VAL,
           PKEY_SRC_OBJECT, PTY_REL_FK
      FROM WRK_ECI_ALT_S40_READY
     WHERE grp_ssn_exc AND uq_ssn_exc;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 50c. Invalid Medicaid id -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, MAPPING_NAME, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, SRC_SYS_ID_2, SRC_SYS_ID_1)
    SELECT src_sys, run_ts, medicaid_exception_type, medicaid_exception_code, medicaid_exception_desc,
           mapping_name, ALT_ID_VAL, attr_medicaid, PTY_REL_FK, PKEY_SRC_OBJECT
      FROM WRK_ECI_ALT_S40_READY
     WHERE grp_mcd_exc AND uq_mcd_exc;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    l_rows := l_pub_rows;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_ECI_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid alternate ids and SSN / Medicaid exception rows. '
        || 'Count shown is rows inserted across all publish branches.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail('ECI', :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
