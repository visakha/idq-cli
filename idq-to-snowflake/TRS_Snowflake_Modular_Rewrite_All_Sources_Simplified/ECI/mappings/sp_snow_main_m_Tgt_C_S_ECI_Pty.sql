-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads the active ECI child and family parties of the delta into the
--   party and party-role tables, and logs demographic exceptions. An
--   exception never rejects the party: the party is loaded AND logged
--   (a future birth date is loaded as NULL). Ethnicity, race and
--   language exceptions apply to child rows only.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src ->
--   exp_load -> active -> dq -> dq2 -> routed -> final SELECT), one
--   transaction, one log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_PTY_S10_SRC      child + family delta rows, party
--                                     key, party type and source full
--                                     name
--   Step 20  WRK_ECI_PTY_S20_ACTIVE   active parties only (no
--                                     deactivation status)
--   Step 30  WRK_ECI_PTY_S30_DQ       name standardisation, gender,
--                                     birth date, ethnicity, race
--                                     indicators, language
--   Step 40  WRK_ECI_PTY_S40_DQ2      standardised fields unpacked and
--                                     every rule's exception
--                                     description/type resolved
--   Step 50  WRK_ECI_PTY_S50_READY    routed groups, party/role keys
--                                     and insert-only guards
--   Step 60  PUBLISH                targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_PTY_S10_SRC, WRK_ECI_PTY_S20_ACTIVE,
--   WRK_ECI_PTY_S30_DQ, WRK_ECI_PTY_S40_DQ2, WRK_ECI_PTY_S50_READY.
--   They live in the same schema as the targets (unqualified names, as
--   in the original code) and are prefixed WRK_ECI_. They survive a
--   session crash (TRANSIENT, not TEMP), which is what makes inspection
--   after a run possible. No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. IDQ truncates C_S_ECI_PTY / C_S_ECI_PTY_RLE;
--     the Snowflake version instead skips keys already present
--     (uq_pty / uq_rle guards).
--   * Exception rows carry the literal mapping name
--     'm_Tgt_C_S_ECI_Pty_OnGoing' (the IDQ expressions write that
--     literal, not this mapping's name); preserved via c_exc_mapping.
--   * The source read also stores a filter on five child ids; it is
--     not part of the custom query and is ignored, as in IDQ (custom
--     query mode) and as in the original; preserved.
--   * The stored inactive filter condition is written as a comment
--     ("--not IsNull(...)"), so ACTIVE parties are kept; preserved as
--     the NOT EXISTS filter in step 20.
--   * VERSION_SEQ is hard-coded to 1 on both targets. The party
--     consolidation step also computes a duplicate rank and a
--     demographics MD5 for the timeline in IDQ; neither is written by
--     IDQ, so neither is computed here; preserved.
--   * Party PERIOD_START_DATE is source DATE_MODIFIED (DATE_MODIFIED,
--     else DATE_CREATED); role PERIOD_START_DATE is DATE_CREATED;
--     preserved.
--   * Gender exceptions are routed on the looked-up description, so an
--     unconfigured code writes no row; ethnicity, race and language
--     exceptions are routed on the returned code (or its description),
--     so an unconfigured exception writes no row; preserved.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so
--   every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'ECI';
    c_workflow   VARCHAR DEFAULT 'wf_ECI_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty';
    c_exc_mapping VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_OnGoing';
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
    DROP TABLE IF EXISTS WRK_ECI_PTY_S10_SRC;
    DROP TABLE IF EXISTS WRK_ECI_PTY_S20_ACTIVE;
    DROP TABLE IF EXISTS WRK_ECI_PTY_S30_DQ;
    DROP TABLE IF EXISTS WRK_ECI_PTY_S40_DQ2;
    DROP TABLE IF EXISTS WRK_ECI_PTY_S50_READY;

    -- ---- Step 10: CHILD + FAMILY DELTA ROWS ------------------------------
    -- Purpose: the delta parties with their party key, party type and
    -- source full name. This is the original src + Exp_ECI_Data_Load
    -- CTEs. DATE_MODIFIED is already coalesced to DATE_CREATED here,
    -- as in the original src CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PTY_S10_SRC AS
    WITH
    src AS (
        SELECT 'ECI_CHILD' AS SOURCE_TABLE, child.ID_CHILD AS ID, child.CHILD_SSN, child.FIRST_NAME,
               child.LAST_NAME, child.MIDDLE_INITIAL, child.DOB, child.GESTATION_AGE, child.GENDER,
               child.BIRTH_WT_LB, child.BIRTH_WT_OZ, child.INTERPRET_IND, child.LANGUAGE_CD, child.RACE_CD,
               child.DATE_CREATED, COALESCE(child.DATE_MODIFIED, child.DATE_CREATED) AS DATE_MODIFIED,
               child.MODIFIED_BY, child.CREATED_BY, child.ETHNICITY, child.RACE_WHITE, child.RACE_AA,
               child.RACE_ASIAN, child.RACE_PI, child.RACE_AN, child.LOAD_DATE
          FROM STG_ECI_D_CHILD child
        UNION ALL
        SELECT 'ECI_FAMILY', fam.ID_FAMILY, NULL, fam.FIRST_NAME, fam.LAST_NAME, fam.MIDDLE_INITIAL, fam.DOB,
               NULL, fam.GENDER, NULL, NULL, NULL, NULL, NULL, fam.DATE_CREATED,
               COALESCE(fam.DATE_MODIFIED, fam.DATE_CREATED), fam.MODIFIED_BY, fam.CREATED_BY, NULL, NULL,
               NULL, NULL, NULL, NULL, fam.LOAD_DATE
          FROM STG_ECI_D_FAMILY fam
    )
    SELECT s.*,
           LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')  AS pkey_src_object,
           'Indv' AS party_type,
           'ECI'  AS src_system,
           TRIM(NVL(s.FIRST_NAME, '')
                || IFF(s.MIDDLE_INITIAL IS NOT NULL, ' ' || TRIM(s.MIDDLE_INITIAL), '')
                || ' ' || NVL(LTRIM(s.LAST_NAME), ''))                                      AS src_full_name
      FROM src s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PTY_S10_SRC;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_DELTA_PARTIES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PTY_S10_SRC', 'CREATED',
        'Child and family delta parties with party keys and source full names. '
        || 'Read by the active filter; the delta tables are not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_DELTA_PARTIES', :l_rows) || CHR(10);

    -- ---- Step 20: ACTIVE PARTIES ONLY ------------------------------------
    -- Purpose: drop parties that have a deactivation status. This is
    -- the original active CTE (lookup on STG_ECI_PTY_INACTIVE_STS plus
    -- the inactive filter).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PTY_S20_ACTIVE AS
    SELECT e.*
      FROM WRK_ECI_PTY_S10_SRC e
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = e.pkey_src_object AND i.ROWID_SYSTEM = e.src_system
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PTY_S20_ACTIVE;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'ACTIVE_PARTIES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PTY_S20_ACTIVE', 'CREATED',
        'Active parties only: parties with a deactivation status are removed. '
        || 'Read by the validation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 ACTIVE_PARTIES', :l_rows) || CHR(10);

    -- ---- Step 30: VALIDATION RULES, STEP 1 --------------------------------
    -- Purpose: the rule functions -- name standardisation, gender,
    -- birth date, ethnicity, race indicators, language -- with their
    -- code-value lookups. Reads ONLY step 20. This is the original dq
    -- CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PTY_S30_DQ AS
    WITH
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT a.*,
           fn_snow_helper15_common(a.FIRST_NAME, a.MIDDLE_INITIAL, a.LAST_NAME, a.src_full_name, NULL, NULL,
                                   NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)       AS nm,
           fn_snow_helper17_common(a.GENDER, a.party_type, a.src_system)                       AS gd,
           fn_snow_helper16_common(a.DOB, a.party_type, a.src_system, :l_run_ts) AS birth_exception_code,
           et.MSTR_CODE_VALUE                                                                  AS ethnicity_mstr,
           fn_snow_helper19_common(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
           lg.MSTR_CODE_VALUE                                                                  AS language_mstr
      FROM WRK_ECI_PTY_S20_ACTIVE a
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRST_NAME)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LAST_NAME)) AND jl.IS_LAST_JUNK
      LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = a.src_system
                         AND et.SRC_CODE_VALUE = a.ETHNICITY
      LEFT JOIN lkp_cv lg ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = a.src_system
                         AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PTY_S30_DQ;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'DQ_RULES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PTY_S30_DQ', 'CREATED',
        'Parties with name standardisation, gender, birth-date, ethnicity, race-indicator and '
        || 'language rule results. Read by the exception-resolution step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 DQ_RULES', :l_rows) || CHR(10);

    -- ---- Step 40: VALIDATION RULES, STEP 2 --------------------------------
    -- Purpose: unpack the standardised fields and resolve every rule's
    -- exception code, description and type from the exception catalogue.
    -- A future birth date becomes NULL here. Reads ONLY step 30. This
    -- is the original dq2 CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PTY_S40_DQ2 AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT d.*,
           d.nm:first_name::VARCHAR                       AS std_first_name,
           d.nm:middle_name::VARCHAR                      AS std_mdl_name,
           d.nm:last_name::VARCHAR                        AS std_lst_name,
           d.nm:full_name::VARCHAR                        AS std_full_name,
           d.nm:src_full_name::VARCHAR                    AS std_src_full_name,
           d.nm:prfx_name::VARCHAR                        AS std_prfx_name,
           d.gd:mdm_gender_code::VARCHAR                  AS mdm_gender_code,
           d.gd:exception_code::VARCHAR                   AS gender_exception_code,
           xg.EXCEPTION_DESC                              AS gender_exception_description,
           xg.EXCEPTION_TYPE                              AS gender_exception_type,
           IFF(d.birth_exception_code IS NULL, d.DOB, NULL) AS std_birth_date,
           xb.EXCEPTION_DESC                              AS birth_exception_description,
           xb.EXCEPTION_TYPE                              AS birth_exception_type,
           xe.EXCEPTION_CODE                              AS ethnicity_exception_code,
           xe.EXCEPTION_DESC                              AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE                              AS ethnicity_exception_type,
           d.rc:mdm_race_cd::VARCHAR                      AS mdm_race_cd,
           d.rc:src_race_ind_list::VARCHAR                AS src_race_ind_list,
           xr.EXCEPTION_CODE                              AS race_exception_cd,
           xr.EXCEPTION_DESC                              AS race_exception_desc,
           xr.EXCEPTION_TYPE                              AS race_exception_type,
           xl.EXCEPTION_CODE                              AS language_exception_code,
           xl.EXCEPTION_DESC                              AS language_exception_desc,
           xl.EXCEPTION_TYPE                              AS language_exception_type
      FROM WRK_ECI_PTY_S30_DQ d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = d.rc:exception_code::VARCHAR
      LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language');
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PTY_S40_DQ2;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'DQ_EXCEPTIONS_RESOLVED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_PTY_S40_DQ2', 'CREATED',
        'Standardised parties with every exception code, description and type resolved. '
        || 'Read by the routing step.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 DQ_EXCEPTIONS_RESOLVED', :l_rows) || CHR(10);

    -- ---- Step 50: ROUTED + READY -------------------------------------------
    -- Purpose: the router groups (every active party loads; each failed
    -- rule additionally logs an exception; ethnicity, race and language
    -- only for child rows), the trimmed party key and role key, and the
    -- insert-only guards (key not yet in the target, first row per key
    -- in this run). Reads ONLY step 40. This is the original routed
    -- CTE plus the final SELECT (including the target-table guard
    -- joins, which still see the pre-run state because nothing has
    -- been published yet).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_PTY_S50_READY AS
    WITH
    routed AS (
        SELECT d.*,
               TRIM(d.pkey_src_object)                                   AS pkey_trim,
               TRIM(d.pkey_src_object) || '|' || :P_RLE_BO_CLASS_CD_MEMBER AS rle_pkey,
               d.gender_exception_description IS NOT NULL                AS grp_gender,
               d.birth_exception_code IS NOT NULL                        AS grp_birth,
               (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD') AS grp_ethnicity,
               (d.race_exception_desc IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD')      AS grp_race,
               (d.language_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD')  AS grp_language
          FROM WRK_ECI_PTY_S40_DQ2 d
    )
    SELECT r.*,
           1                                                        AS version_seq,
           1                                                        AS hub_state_ind,
           :l_run_ts                                                AS run_ts,
           :c_exc_mapping                                           AS exc_mapping,
           :P_PTY_BO_CLASS_CD_MEMBER                                AS pty_bo_class_cd,
           :P_RLE_BO_CLASS_CD_MEMBER                                AS rle_bo_class_cd,
           r.BIRTH_WT_LB * 453.6 + r.BIRTH_WT_OZ * 28.35            AS birth_wght_grms,
           TO_VARCHAR(r.DOB, 'MM/DD/YYYY')                          AS dob_text,
           'Gender'                                                 AS attr_gender,
           'Birth Date'                                             AS attr_birth,
           'Ethnicity_Cd'                                           AS attr_ethnicity,
           'Race_Cd'                                                AS attr_race,
           'Language_Cd'                                            AS attr_language,
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                         AS uq_pty,
           (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL)                        AS uq_rle,
           ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.pkey_src_object, r.ID, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.ID) = 1        AS uq_gender,
           ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.pkey_src_object, r.ID, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.ID) = 1         AS uq_birth,
           ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.pkey_src_object, r.ID,
                                           r.ethnicity_exception_type, r.ethnicity_exception_code
                                  ORDER BY r.ID) = 1                                         AS uq_ethnicity,
           ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.pkey_src_object, r.ID, r.race_exception_type,
                                           r.race_exception_cd ORDER BY r.ID) = 1            AS uq_race,
           ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.pkey_src_object, r.ID,
                                           r.language_exception_type, r.language_exception_code
                                  ORDER BY r.ID) = 1                                         AS uq_language
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_PTY_S50_READY;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'ROUTED_READY', 'COMPLETED', 'C_S_ECI_PTY, C_S_ECI_PTY_RLE, EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_ECI_PTY_S50_READY', 'CREATED',
        'Publish-ready parties: router groups, party/role keys and insert-only guards (uq_pty, '
        || 'uq_rle, uq_gender, uq_birth, uq_ethnicity, uq_race, uq_language). Published in step 60.',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 ROUTED_READY', :l_rows) || CHR(10);

    -- ---- Step 60: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The seven INSERTs below are
    -- the seven branches of the original INSERT ALL, in the same order
    -- (party, role, gender, birth date, ethnicity, race, language),
    -- with the same column lists, values and WHERE conditions -- only
    -- the source changed, from the final SELECT to step 50. No
    -- TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    -- 60a. Valid parties -> C_S_ECI_PTY
    INSERT INTO C_S_ECI_PTY
           (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            PTY_BO_CLASS_CD, PRFX_NM, FULL_NM, LST_NM, MDL_NM, FRST_NM, GNDR_CD, BIRTH_DT, SRC_FULL_NM,
            SRC_LAST_UPD_DT, BIRTH_WGHT_GRMS, HUB_STATE_IND, SRC_ETHNCTY, ETHNCTY, RACE_CD, PRFRD_LANG_CD,
            SRC_PRFRD_LANG_CD, SRC_RACE_CD, PERIOD_START_DATE)
    SELECT pkey_trim, version_seq, run_ts, MODIFIED_BY, DATE_CREATED, CREATED_BY, pkey_trim,
           pty_bo_class_cd, std_prfx_name, std_full_name, std_lst_name, std_mdl_name, std_first_name,
           mdm_gender_code, std_birth_date, std_src_full_name, DATE_MODIFIED, birth_wght_grms,
           hub_state_ind, ETHNICITY, ethnicity_mstr, mdm_race_cd, language_mstr, LANGUAGE_CD,
           src_race_ind_list, DATE_MODIFIED
      FROM WRK_ECI_PTY_S50_READY
     WHERE uq_pty;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60b. Valid roles -> C_S_ECI_PTY_RLE
    INSERT INTO C_S_ECI_PTY_RLE
           (PKEY_SRC_OBJECT, LAST_UPDATE_DATE, CREATOR, CREATE_DATE, VERSION_SEQ, PTY_FK, SRC_LAST_UPD_DT,
            RLE_BO_CLASS_CD, PERIOD_START_DATE, HUB_STATE_IND, SRC_ROWID)
    SELECT rle_pkey, run_ts, CREATED_BY, DATE_CREATED, version_seq, pkey_trim, DATE_MODIFIED,
           rle_bo_class_cd, DATE_CREATED, hub_state_ind, rle_pkey
      FROM WRK_ECI_PTY_S50_READY
     WHERE uq_rle;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60c. Invalid gender -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE)
    SELECT src_system, gender_exception_type, gender_exception_code, gender_exception_description,
           attr_gender, GENDER, exc_mapping, pkey_src_object, ID, GENDER, DOB, run_ts
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_gender AND uq_gender;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60d. Invalid birth date -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_system, pkey_src_object, birth_exception_code, birth_exception_description,
           birth_exception_type, run_ts, exc_mapping, GENDER, attr_birth, ID, std_prfx_name,
           FIRST_NAME, LAST_NAME, MIDDLE_INITIAL, dob_text, DOB
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_birth AND uq_birth;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60e. Invalid ethnicity -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
            SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
            SRC_SYS_ID_2, ATTRIBUTE_VALUE)
    SELECT run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
           attr_ethnicity, GENDER, pkey_src_object, src_system, FIRST_NAME, std_lst_name, std_mdl_name,
           exc_mapping, DOB, DATE_CREATED, ID, ETHNICITY
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_ethnicity AND uq_ethnicity;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60f. Invalid race -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
            MAPPING_NAME, ATTRIBUTE_VALUE)
    SELECT ID, pkey_src_object, src_system, race_exception_cd, race_exception_desc, race_exception_type,
           run_ts, FIRST_NAME, std_mdl_name, std_lst_name, GENDER, DOB, attr_race, std_prfx_name,
           DATE_CREATED, exc_mapping, src_race_ind_list
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_race AND uq_race;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60g. Invalid language -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, PERIOD_START_DATE)
    SELECT src_system, pkey_src_object, ID, language_exception_type, language_exception_code,
           language_exception_desc, run_ts, FIRST_NAME, std_mdl_name, std_lst_name, std_birth_date,
           GENDER, attr_language, LANGUAGE_CD, exc_mapping, DATE_CREATED
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_language AND uq_language;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    l_rows := l_pub_rows;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'PUBLISH', 'COMPLETED',
        'C_S_ECI_PTY, C_S_ECI_PTY_RLE, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: parties, roles and all demographic exception classes. '
        || 'Count shown is rows inserted across all publish branches.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_ECI_Pty completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_ECI_Pty failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
