-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads phones and e-mail addresses of the ECI parties into the
--   phone and e-mail tables. E-mail rows are validated as e-mails;
--   every other row (including a NULL type) is treated as a phone and
--   standardised. A phone with a missing area code is both loaded AND
--   logged, and a bad phone or e-mail is only logged.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> active
--   -> dq -> checked -> routed -> final SELECT), one transaction, one
--   log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_PHN_S10_SRC      phone / e-mail source rows with
--                                     party, role and record keys
--   Step 20  WRK_ECI_PHN_S20_ACTIVE   rows whose party is not
--                                     deactivated
--   Step 30  WRK_ECI_PHN_S30_DQ       cleaned phones (7-digit numbers
--                                     get '000' prefixed) and validated
--                                     e-mails
--   Step 40  WRK_ECI_PHN_S40_ROUTED   area-code lookup, phone exception
--                                     codes and router groups
--   Step 50  WRK_ECI_PHN_S50_READY    publish-ready rows with
--                                     insert-only guards
--   Step 60  PUBLISH                targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_PHN_S10_SRC, WRK_ECI_PHN_S20_ACTIVE, WRK_ECI_PHN_S30_DQ,
--   WRK_ECI_PHN_S40_ROUTED, WRK_ECI_PHN_S50_READY. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Keys already present are skipped (uq_phn /
--     uq_eaddr guards).
--   * A 'Missing_AreaCode' phone matches both phone groups, so it is
--     loaded AND logged; preserved (grp_phone_good includes it and
--     grp_phone_bad includes every non-NULL code).
--   * An e-mail whose 'Invalid_Email' code is not configured in the
--     exception catalogue is treated as valid and loaded, because the
--     router tests the looked-up code; preserved.
--   * The phone exception SRC_SYS_ID_1 is written NULL (linked to an
--     unfed port in IDQ) and its type is the literal 'Bad Value';
--     preserved. The phone is written cleaned and cut to 10 characters
--     (port precision of the rule); preserved via fn_snow_helper23_common.
--   * VERSION_SEQ is '1' on both targets; PERIOD_START_DATE is source
--     PERIOD_START_DATE; the e-mail PERIOD_REFERENCE_TIME port is not
--     fed (NULL); preserved.
--   * The area-code lookup (fn_snow_helper44_common) reads the phone
--     area-code reference table; its internal table reference is a
--     framework/install concern (see the step map), not changed here.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr';
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
    DROP TABLE IF EXISTS WRK_ECI_PHN_S10_SRC;
    DROP TABLE IF EXISTS WRK_ECI_PHN_S20_ACTIVE;
    DROP TABLE IF EXISTS WRK_ECI_PHN_S30_DQ;
    DROP TABLE IF EXISTS WRK_ECI_PHN_S40_ROUTED;
    DROP TABLE IF EXISTS WRK_ECI_PHN_S50_READY;

    -- ---- Step 10: PHONE / E-MAIL SOURCE ROWS ------------------------------
    -- Purpose: the source rows with the party key, role key, record
    -- key (trimmed phone/e-mail) and source row id (untrimmed
    -- phone/e-mail). This is the original src CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PHN_S10_SRC AS
    SELECT s.SOURCE_TABLE, s.WORK_EXT, s.PHONE_TP, s.USG_TP, s.PREF_LVL, s.PERIOD_START_DATE,
           s.PHONE_EMAIL_TYPE, s.PHONE_EMAIL, s.ID_CASE, s.ID, s.ID_FAMILY_PHONE,
           NVL(s.PHONE_EMAIL_TYPE = 'EADDRESS', FALSE)                                    AS is_email,
           NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')      AS pty_src_key,
           NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member' AS pty_rle_fk,
           IFF(NVL(s.PHONE_EMAIL_TYPE = 'EADDRESS', FALSE),
               NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|001|'
               || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '') || '|' || NVL(TRIM(s.PHONE_EMAIL), ''),
               NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|'
               || NVL(s.PHONE_TP, '') || '|' || NVL(s.USG_TP, '') || '|' || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '')
               || '|' || NVL(TRIM(s.PHONE_EMAIL), ''))                                     AS pkey_src_object,
           IFF(NVL(s.PHONE_EMAIL_TYPE = 'EADDRESS', FALSE),
               NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|001|'
               || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '') || '|' || NVL(s.PHONE_EMAIL, ''),
               NVL(TO_VARCHAR(s.ID), '') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member|'
               || NVL(s.PHONE_TP, '') || '|' || NVL(s.USG_TP, '') || '|' || NVL(TO_VARCHAR(s.ID_FAMILY_PHONE), '')
               || '|' || NVL(s.PHONE_EMAIL, ''))                                           AS src_rowid
      FROM V_ECI_ETL_SRC_FAMILY_PHONE s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PHN_S10_SRC;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_PHN_EADDR', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PHN_S10_SRC', 'CREATED',
        'Phone and e-mail source rows with party, role and record keys. '
        || 'Read by the active filter; the source view is not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_PHN_EADDR', :l_rows) || CHR(10);

    -- ---- Step 20: ACTIVE PARTIES ONLY ------------------------------------
    -- Purpose: drop rows whose party has a deactivation status. This
    -- is the original active CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PHN_S20_ACTIVE AS
    SELECT s.*
      FROM WRK_ECI_PHN_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = s.pty_src_key AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PHN_S20_ACTIVE;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'ACTIVE_PHN_EADDR', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PHN_S20_ACTIVE', 'CREATED',
        'Phone and e-mail rows of active parties only. Read by the validation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 ACTIVE_PHN_EADDR', :l_rows) || CHR(10);

    -- ---- Step 30: CLEAN + VALIDATE -----------------------------------------
    -- Purpose: clean phone numbers (7-digit numbers get '000'
    -- prefixed) and validate e-mail addresses. Reads ONLY step 20.
    -- This is the original dq CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PHN_S30_DQ AS
    SELECT a.*,
           IFF(NOT a.is_email,
               fn_snow_helper23_common(IFF(LENGTH(a.PHONE_EMAIL) = 7, '000' || a.PHONE_EMAIL, a.PHONE_EMAIL)),
               NULL)                                                          AS std_phone,
           IFF(a.is_email, fn_snow_helper22_common(a.PHONE_EMAIL), NULL)       AS em
      FROM WRK_ECI_PHN_S20_ACTIVE a;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PHN_S30_DQ;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'DQ_CLEAN_VALIDATE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PHN_S30_DQ', 'CREATED',
        'Cleaned phones and validated e-mails. Read by the area-code / exception step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 DQ_CLEAN_VALIDATE', :l_rows) || CHR(10);

    -- ---- Step 40: AREA CODE + ROUTER GROUPS ---------------------------------
    -- Purpose: the phone area-code lookup and phone exception code,
    -- the e-mail exception lookup, and the four router groups (good
    -- phone, bad phone, good e-mail, bad e-mail). Reads ONLY step 30.
    -- This is the original checked + routed CTEs.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PHN_S40_ROUTED AS
    WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
    checked AS (
        SELECT d.*,
               IFF(NOT d.is_email,
                   fn_snow_helper24_common(d.std_phone, 'ECI', d.USG_TP, ar.NPA_ID, ar.SERVICE), NULL) AS phone_exception_code,
               d.em:email_address::VARCHAR                                        AS std_email
          FROM WRK_ECI_PHN_S30_DQ d
          LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.std_phone, 1, 3)
    )
    SELECT c.*,
           xp.EXCEPTION_DESC                                                  AS phone_exception_desc,
           xe.EXCEPTION_CODE                                                  AS email_exception_code,
           xe.EXCEPTION_DESC                                                  AS email_exception_desc,
           xe.EXCEPTION_TYPE                                                  AS email_exception_type,
           (NOT c.is_email AND (c.phone_exception_code IS NULL
                                OR c.phone_exception_code = 'Missing_AreaCode')) AS grp_phone_good,
           (NOT c.is_email AND c.phone_exception_code IS NOT NULL)            AS grp_phone_bad,
           (c.is_email AND xe.EXCEPTION_CODE IS NULL)                          AS grp_email_good,
           (c.is_email AND xe.EXCEPTION_CODE IS NOT NULL)                      AS grp_email_bad
      FROM checked c
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = c.em:exception_code::VARCHAR;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PHN_S40_ROUTED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'ROUTED_GROUPS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PHN_S40_ROUTED', 'CREATED',
        'Phone and e-mail rows sorted into good / bad groups, with exception descriptions resolved. '
        || 'Read by the ready step.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ROUTED_GROUPS', :l_rows) || CHR(10);

    -- ---- Step 50: READY -- guards + exception details -----------------------
    -- Purpose: the publish-ready rows -- version, hub state, exception
    -- detail columns (primary / work / secondary phone, phone
    -- attribute name, e-mail type/status flags) and the insert-only
    -- guards. Reads ONLY step 40. This is the original final SELECT
    -- (including the target-table guard joins, which still see the
    -- pre-run state because nothing has been published yet).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PHN_S50_READY AS
    SELECT r.*,
           '1' /* TIMELINE: VERSION_SEQ */                                     AS version_seq,
           1                                                                    AS hub_state_ind,
           'ECI'                                                                AS src_sys,
           :l_run_ts                                                            AS run_ts,
           :c_mapping                                                           AS mapping_name,
           'Bad Value'                                                          AS exc_type_bad_value,
           IFF(r.PREF_LVL = 'Primary', r.std_phone, NULL)                       AS exc_primary_phone,
           IFF(r.USG_TP = 'Work', r.std_phone, NULL)                            AS exc_work_phone,
           IFF(r.PREF_LVL = 'Secondary', r.std_phone, NULL)                     AS exc_secondary_phone,
           DECODE(r.USG_TP, '001', 'Main Phone', '002', 'Work Phone', '003', 'Other Phone') AS exc_phone_attribute,
           'Email'                                                              AS exc_email_attribute,
           '001'                                                                AS eaddr_addr_tp,
           'Active'                                                             AS eaddr_sts_cd,
           'Y'                                                                  AS eaddr_is_vld,
           (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.pkey_src_object
                                   ORDER BY r.PERIOD_START_DATE DESC, r.ID_FAMILY_PHONE) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL)                                    AS uq_phn,
           (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.pkey_src_object
                                   ORDER BY r.PERIOD_START_DATE DESC, r.ID_FAMILY_PHONE) = 1
            AND xea.PKEY_SRC_OBJECT IS NULL)                                    AS uq_eaddr,
           ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.ID_CASE, r.USG_TP, r.phone_exception_code
                                  ORDER BY r.ID_FAMILY_PHONE) = 1               AS uq_phone_exc,
           ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.ID_FAMILY_PHONE, r.email_exception_type,
                                           r.email_exception_code ORDER BY r.ID) = 1 AS uq_email_exc
      FROM WRK_ECI_PHN_S40_ROUTED r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = r.pkey_src_object
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
             ON xea.PKEY_SRC_OBJECT = r.pkey_src_object;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PHN_S50_READY;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'READY_TO_PUBLISH', 'COMPLETED', 'C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR, EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_ECI_PHN_S50_READY', 'CREATED',
        'Publish-ready phones and e-mails with insert-only guards (uq_phn, uq_eaddr, '
        || 'uq_phone_exc, uq_email_exc). Published in step 60.',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 60: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The four INSERTs below are
    -- the four branches of the original INSERT ALL, in the same order
    -- (good phone, bad phone, good e-mail, bad e-mail), with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final SELECT to step 50. No TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    -- 60a. Good phones -> C_S_ECI_PTY_RLE_PHN
    INSERT INTO C_S_ECI_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, PHN_NUM_EXT, HUB_STATE_IND)
    SELECT pkey_src_object, PERIOD_START_DATE, version_seq, run_ts, run_ts, src_rowid, pty_rle_fk, PHONE_TP,
           USG_TP, std_phone, PREF_LVL, PERIOD_START_DATE, WORK_EXT, hub_state_ind
      FROM WRK_ECI_PHN_S50_READY
     WHERE grp_phone_good AND uq_phn;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60b. Bad phones -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
            SRC_SYS_ID_2, ATTRIBUTE_NAME)
    SELECT src_sys, phone_exception_code, phone_exception_desc, run_ts, exc_primary_phone, exc_work_phone,
           exc_secondary_phone, mapping_name, NULL, exc_type_bad_value, USG_TP, PERIOD_START_DATE,
           std_phone, ID_CASE, exc_phone_attribute
      FROM WRK_ECI_PHN_S50_READY
     WHERE grp_phone_bad AND uq_phone_exc;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60c. Good e-mails -> C_S_ECI_PTY_RLE_EADDR
    INSERT INTO C_S_ECI_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, VERSION_SEQ, HUB_STATE_IND)
    SELECT pkey_src_object, PERIOD_START_DATE, NULL, run_ts, run_ts, pkey_src_object, pty_rle_fk,
           std_email, NULL, eaddr_addr_tp, eaddr_sts_cd, eaddr_is_vld, PERIOD_START_DATE, version_seq,
           hub_state_ind
      FROM WRK_ECI_PHN_S50_READY
     WHERE grp_email_good AND uq_eaddr;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60d. Bad e-mails -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME,
            EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
    SELECT src_sys, ID_FAMILY_PHONE, email_exception_code, email_exception_desc, run_ts, PHONE_EMAIL,
           mapping_name, email_exception_type, PERIOD_START_DATE, PHONE_EMAIL, exc_email_attribute
      FROM WRK_ECI_PHN_S50_READY
     WHERE grp_email_bad AND uq_email_exc;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    l_rows := l_pub_rows;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'PUBLISH', 'COMPLETED',
        'C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: good phones, bad-phone exceptions, good e-mails and '
        || 'bad-e-mail exceptions. Count shown is rows inserted across all publish branches.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
