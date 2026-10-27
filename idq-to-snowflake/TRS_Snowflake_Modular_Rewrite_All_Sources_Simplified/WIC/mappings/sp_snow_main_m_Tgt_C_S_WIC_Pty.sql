-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty  --  MODULAR REWRITE
--
-- Original: IDQ mapping m_Tgt_C_S_WIC_Pty, workflow wf_WIC_Stage_Load.
-- Original Snowflake procedure sp_snow_main_m_Tgt_C_S_WIC_Pty.
--
-- What this mapping does, in plain words: it loads the active WIC
-- parties in V_WIC_ETL_SRC into the party and party-role tables, and
-- logs demographic exceptions. A party is active when it has no
-- deactivation status. Every active party loads (an exception never
-- rejects the party -- it is loaded AND logged). Gender, ethnicity and
-- race exceptions are logged only for SOURCE_TABLE 'CLIENT'; birth
-- date and language exceptions are logged for every row.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (active -> dq ->
--   dq2 -> routed -> final SELECT), one transaction, one log line at
--   the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_WIC_PTY_S10_ACTIVE  active source parties only (the
--                                   deactivation-status filter)
--   Step 20  WRK_WIC_PTY_S20_DQ      name standardisation, gender, birth
--                                   date, ethnicity, race indicators,
--                                   language
--   Step 30  WRK_WIC_PTY_S30_DQ2     standardised values pulled out +
--                                   exception descriptions / types
--                                   resolved
--   Step 40  WRK_WIC_PTY_S40_ROUTED  party / role keys, exception routing
--                                   groups, run constants, and the
--                                   insert-only guards (uq_pty, uq_rle,
--                                   uq_gender, uq_birth, uq_ethnicity,
--                                   uq_race, uq_language)
--   Step 50  PUBLISH                targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_WIC_PTY_S10_ACTIVE, WRK_WIC_PTY_S20_DQ, WRK_WIC_PTY_S30_DQ2,
--   WRK_WIC_PTY_S40_ROUTED. They live in the same schema as the targets
--   (unqualified names, as in the original code), are prefixed WRK_WIC_,
--   and are registered in JOB_CONTROL_ETL at creation. They survive a
--   session crash (TRANSIENT, not TEMP), which is what makes inspection
--   after a run possible. A Snowflake CURSOR was NOT used: cursors
--   process row by row, and every step here is set-based by design --
--   the work table IS the result set, held as a table instead of in
--   memory, so it can be counted and inspected after the run.
--
-- INSTALL LOCATION
--   Install schema is WIC_ETL_WRK in database MDM_ETL_WIC. All table
--   names in the code below are unqualified, exactly as in the original.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ truncate of C_S_WIC_PTY and
--     C_S_WIC_PTY_RLE is NOT performed; instead keys already present
--     are skipped (uq_pty / uq_rle guards).
--   * PRESERVED: an exception never rejects the party (loaded AND
--     logged), exactly as in the original.
--   * PRESERVED: C_S_WIC_PTY.BIRTH_DT is the source DOB (the IDQ link
--     is the source port); the language exception row writes the
--     mapplet's birth date (NULL for a future one), while the
--     birth-date exception row writes the source DOB.
--   * PRESERVED: birth weight in grams is BIRTH_WT_OZ * 28.35 (ounces
--     only, the deliberate 3/14/2025 change noted in the original).
--   * PRESERVED: VERSION_SEQ is hard-coded to 1 and
--     PERIOD_START_DATE = DATEKEY.
--   * PRESERVED: the insert-only guards (uq_*) are evaluated in step
--     40, before the publish transaction, against the targets as they
--     stand at that point -- the same snapshot behaviour as the
--     original single INSERT ALL, whose source query was evaluated
--     once before any branch inserted.
--   * PRESERVED: HUB_STATE_IND is hard-coded to 1 in the final SELECT,
--     exactly as in the original.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',   -- $RLE_BO_CLASS_CD_Member
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'WIC';
    c_workflow   VARCHAR DEFAULT 'wf_WIC_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty';
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
    DROP TABLE IF EXISTS WRK_WIC_PTY_S10_ACTIVE;
    DROP TABLE IF EXISTS WRK_WIC_PTY_S20_DQ;
    DROP TABLE IF EXISTS WRK_WIC_PTY_S30_DQ2;
    DROP TABLE IF EXISTS WRK_WIC_PTY_S40_ROUTED;

    -- ---- Step 10: ACTIVE -- deactivation filter --------------------------
    -- Purpose: active source parties only. A party is excluded when it
    -- has a deactivation-status row. This is the only step that reads
    -- V_WIC_ETL_SRC; every later step reads work tables.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PTY_S10_ACTIVE AS
    SELECT v.SOURCE_TABLE, v.DATEKEY, v.LOAD_DATE, v.ID, v.PTY_SRC_KEY, v.FIRST_NAME, v.LAST_NAME,
           v.MIDDLE_NAME, v.DOB, v.GENDER, v.BIRTH_WT_LB, v.BIRTH_WT_OZ, v.LANGUAGE_CD, v.ETHNICITY,
           v.RACE_WHITE_IND, v.RACE_AA_IND, v.RACE_ASIAN_IND, v.RACE_PI_IND, v.RACE_AN_IND
      FROM V_WIC_ETL_SRC v
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PTY_S10_ACTIVE;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PTY_S10_ACTIVE', 'CREATED',
        'Active source parties only: parties with a deactivation status are removed. '
        || 'Read by the data-quality step; the source view is not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: DQ -- standardise + validate ---------------------------
    -- Purpose: name standardisation, gender, birth date, ethnicity,
    -- race indicators and language for every active party. Reads ONLY
    -- step 10 (plus the reference lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PTY_S20_DQ AS
    WITH
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT a.*,
           fn_snow_helper15_common(a.FIRST_NAME, a.MIDDLE_NAME, a.LAST_NAME,
               TRIM(NVL(a.FIRST_NAME, '') || IFF(a.MIDDLE_NAME IS NOT NULL, ' ' || TRIM(a.MIDDLE_NAME), '')
                    || ' ' || NVL(LTRIM(a.LAST_NAME), '')),
               NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)        AS nm,
           fn_snow_helper17_common(a.GENDER, 'Indv', 'WIC')                            AS gd,
           /* VALIDATION */ fn_snow_helper16_common(a.DOB, 'Indv', 'WIC', :l_run_ts)  AS birth_exception_code,
           et.MSTR_CODE_VALUE                                                          AS ethnicity_mstr,
           fn_snow_helper19_common(a.RACE_WHITE_IND, a.RACE_AA_IND, a.RACE_ASIAN_IND, a.RACE_PI_IND,
                                   a.RACE_AN_IND)                                      AS rc,
           lg.MSTR_CODE_VALUE                                                          AS language_mstr
      FROM WRK_WIC_PTY_S10_ACTIVE a
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRST_NAME)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LAST_NAME)) AND jl.IS_LAST_JUNK
      LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'WIC' AND et.SRC_CODE_VALUE = a.ETHNICITY
      LEFT JOIN lkp_cv lg ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = 'WIC' AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PTY_S20_DQ;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DQ_STANDARDISE_VALIDATE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PTY_S20_DQ', 'CREATED',
        'Standardised names, gender, birth date, ethnicity, race indicators and language for every '
        || 'active party, with exception codes computed. Read by the exception-resolution step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DQ', :l_rows) || CHR(10);

    -- ---- Step 30: DQ2 -- resolved exception descriptions -----------------
    -- Purpose: pull the standardised values out of the name / gender /
    -- race objects and resolve every exception description and type
    -- from the exception lookup. The birth-date value used downstream
    -- is NULL when the birth date itself raised an exception.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PTY_S30_DQ2 AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT d.*,
           d.nm:first_name::VARCHAR          AS std_first_name,
           d.nm:middle_name::VARCHAR         AS std_mdl_name,
           d.nm:last_name::VARCHAR           AS std_lst_name,
           d.nm:full_name::VARCHAR           AS std_full_name,
           d.nm:src_full_name::VARCHAR       AS std_src_full_name,
           d.nm:prfx_name::VARCHAR           AS std_prfx_name,
           d.gd:mdm_gender_code::VARCHAR     AS mdm_gender_code,
           d.gd:exception_code::VARCHAR      AS gender_exception_code,
           xg.EXCEPTION_DESC                 AS gender_exception_description,
           xg.EXCEPTION_TYPE                 AS gender_exception_type,
           /* BAD DATA */ IFF(d.birth_exception_code IS NULL, d.DOB, NULL) AS std_birth_date,
           xb.EXCEPTION_DESC                 AS birth_exception_description,
           xb.EXCEPTION_TYPE                 AS birth_exception_type,
           xe.EXCEPTION_CODE                 AS ethnicity_exception_code,
           xe.EXCEPTION_DESC                 AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE                 AS ethnicity_exception_type,
           d.rc:mdm_race_cd::VARCHAR         AS mdm_race_cd,
           d.rc:src_race_ind_list::VARCHAR   AS src_race_ind_list,
           xr.EXCEPTION_CODE                 AS race_exception_cd,
           xr.EXCEPTION_DESC                 AS race_exception_desc,
           xr.EXCEPTION_TYPE                 AS race_exception_type,
           xl.EXCEPTION_CODE                 AS language_exception_code,
           xl.EXCEPTION_DESC                 AS language_exception_desc,
           xl.EXCEPTION_TYPE                 AS language_exception_type
      FROM WRK_WIC_PTY_S20_DQ d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = d.rc:exception_code::VARCHAR
      LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language');
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PTY_S30_DQ2;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'DQ2_EXCEPTION_DETAIL', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PTY_S30_DQ2', 'CREATED',
        'Standardised values pulled out, with every exception description and type resolved from the '
        || 'exception lookup. Read by the routing step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 DQ2', :l_rows) || CHR(10);

    -- ---- Step 40: ROUTED -- keys, routing groups, guards -----------------
    -- Purpose: the rows that publish will write. Party and role keys
    -- are built, each exception class gets its routing group (gender /
    -- ethnicity / race only for SOURCE_TABLE 'CLIENT'; birth date and
    -- language for every row), run constants are attached, and the
    -- insert-only guards are computed: first row per party / role key
    -- that is not already in the target, and first row per exception
    -- key per class.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_PTY_S40_ROUTED AS
    WITH
    routed AS (
        SELECT d.*,
               TRIM(d.PTY_SRC_KEY)                                                    AS pkey_trim,
               TRIM(d.PTY_SRC_KEY) || '|' || :P_RLE_BO_CLASS_CD_MEMBER                 AS rle_pkey,
               (d.gender_exception_description IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT') AS grp_gender,
               d.birth_exception_code IS NOT NULL                                     AS grp_birth,
               (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT')  AS grp_ethnicity,
               (d.race_exception_desc IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT')       AS grp_race,
               d.language_exception_code IS NOT NULL                                  AS grp_language
          FROM WRK_WIC_PTY_S30_DQ2 d
    )
    SELECT r.*,
           1 /* TIMELINE: VERSION_SEQ hard-coded */         AS version_seq,
           1                                                 AS hub_state_ind,
           'WIC'                                             AS src_sys,
           :l_run_ts                                         AS run_ts,
           :c_mapping                                        AS mapping_name,
           :P_PTY_BO_CLASS_CD_MEMBER                         AS pty_bo_class_cd,
           :P_RLE_BO_CLASS_CD_MEMBER                         AS rle_bo_class_cd,
           r.BIRTH_WT_OZ * 28.35                             AS birth_wght_grms,
           TO_VARCHAR(r.DOB, 'MM/DD/YYYY')                   AS dob_text,
           'Gender'                                          AS attr_gender,
           'Birth Date'                                      AS attr_birth,
           'Ethnicity_Cd'                                    AS attr_ethnicity,
           'Race_Cd'                                         AS attr_race,
           'Language_Cd'                                     AS attr_language,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DATEKEY DESC, r.ID) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                  AS uq_pty,
           (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DATEKEY DESC, r.ID) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL)                 AS uq_rle,
           ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.ID, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.DATEKEY DESC) = 1   AS uq_gender,
           ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.ID, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.DATEKEY DESC) = 1    AS uq_birth,
           ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.ID, r.ethnicity_exception_type,
                                           r.ethnicity_exception_code ORDER BY r.DATEKEY DESC) = 1 AS uq_ethnicity,
           ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.ID, r.race_exception_type,
                                           r.race_exception_cd ORDER BY r.DATEKEY DESC) = 1       AS uq_race,
           ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.PTY_SRC_KEY, r.ID, r.language_exception_type,
                                           r.language_exception_code ORDER BY r.DATEKEY DESC) = 1 AS uq_language
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PTY_S40_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_PTY_S40_ROUTED', 'CREATED',
        'Routed rows: party / role keys, exception routing groups, run constants, and insert-only guards '
        || '(uq_pty, uq_rle, uq_gender, uq_birth, uq_ethnicity, uq_race, uq_language). Read by the publish step; '
        || 'guards are evaluated here, before publish, as in the original single query.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning. The seven INSERTs below are the
    -- seven branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHEN conditions -- only the
    -- source changed, from the original query to step 40.
    BEGIN TRANSACTION;
    -- 50a. Valid party -> C_S_WIC_PTY
    INSERT INTO C_S_WIC_PTY
           (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND, PTY_BO_CLASS_CD,
            BIRTH_WGHT_GRMS, PERIOD_START_DATE, CREATE_DATE, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD,
            BIRTH_DT, SRC_RACE_CD, RACE_CD, ETHNCTY, SRC_ETHNCTY, PRFRD_LANG_CD, SRC_LAST_UPD_DT,
            SRC_PRFRD_LANG_CD, SRC_FULL_NM)
    SELECT pkey_trim, version_seq, run_ts, pkey_trim, hub_state_ind, pty_bo_class_cd, birth_wght_grms,
           DATEKEY, DATEKEY, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name,
           mdm_gender_code, DOB, src_race_ind_list, mdm_race_cd, ethnicity_mstr, ETHNICITY, language_mstr,
           DATEKEY, LANGUAGE_CD, std_src_full_name
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE uq_pty;
    -- 50b. Valid party -> C_S_WIC_PTY_RLE
    INSERT INTO C_S_WIC_PTY_RLE
           (PKEY_SRC_OBJECT, SRC_ROWID, RLE_BO_CLASS_CD, PTY_FK, VERSION_SEQ, LAST_UPDATE_DATE, HUB_STATE_IND,
            CREATE_DATE, PERIOD_START_DATE, SRC_LAST_UPD_DT)
    SELECT rle_pkey, rle_pkey, rle_bo_class_cd, pkey_trim, version_seq, run_ts, hub_state_ind, DATEKEY,
           DATEKEY, DATEKEY
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE uq_rle;
    -- 50c. Invalid gender -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
            LAST_NAME)
    SELECT src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
           GENDER, mapping_name, PTY_SRC_KEY, ID, GENDER, DOB, run_ts, FIRST_NAME, MIDDLE_NAME, LAST_NAME
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE grp_gender AND uq_gender;
    -- 50d. Invalid birth date -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
           run_ts, mapping_name, GENDER, attr_birth, ID, std_prfx_name, FIRST_NAME, LAST_NAME, MIDDLE_NAME,
           dob_text, DOB
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE grp_birth AND uq_birth;
    -- 50e. Invalid ethnicity -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
            SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
            SRC_SYS_ID_2, ATTRIBUTE_VALUE)
    SELECT run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
           attr_ethnicity, GENDER, PTY_SRC_KEY, src_sys, FIRST_NAME, std_lst_name, std_mdl_name,
           mapping_name, DOB, DATEKEY, ID, ETHNICITY
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE grp_ethnicity AND uq_ethnicity;
    -- 50f. Invalid race -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
            MAPPING_NAME, ATTRIBUTE_VALUE)
    SELECT ID, PTY_SRC_KEY, src_sys, race_exception_cd, race_exception_desc, race_exception_type, run_ts,
           FIRST_NAME, std_mdl_name, std_lst_name, GENDER, DOB, attr_race, std_prfx_name, DATEKEY,
           mapping_name, src_race_ind_list
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE grp_race AND uq_race;
    -- 50g. Invalid language -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, PERIOD_START_DATE)
    SELECT src_sys, PTY_SRC_KEY, ID, language_exception_type, language_exception_code,
           language_exception_desc, run_ts, FIRST_NAME, std_mdl_name, std_lst_name, std_birth_date,
           GENDER, attr_language, LANGUAGE_CD, mapping_name, DATEKEY
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE grp_language AND uq_language;
    COMMIT;
    -- Publish row counts by branch are not summed here; report the
    -- routed-row count that fed the publish instead.
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_PTY_S40_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_WIC_PTY, C_S_WIC_PTY_RLE, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid parties, roles, and all exception classes (gender, birth date, '
        || 'ethnicity, race, language). Count shown is routed rows feeding the publish; each branch inserts '
        || 'only its own WHEN-filtered subset, and an exception never stops its party loading.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (routed rows)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_WIC_Pty completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_WIC_Pty failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
