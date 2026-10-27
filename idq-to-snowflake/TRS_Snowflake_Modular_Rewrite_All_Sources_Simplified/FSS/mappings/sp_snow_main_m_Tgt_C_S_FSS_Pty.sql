-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
--
-- What this mapping does, in plain words: it loads the active FSS
-- clients (last active registration, not on the deactivation list) into
-- the party table and the party-role table, and logs demographic
-- exceptions. An exception never rejects the client: it is loaded AND
-- logged. Gender, ethnicity and race exceptions are only written for
-- clients whose source type is CLIENT; birth-date, language and suffix
-- exceptions are written for every row.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> active
--   -> dq -> dq2 -> routed -> final), one transaction, one log line
--   at the end.  If it failed, nothing told you which logical stage
--   had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   No step before publish writes to a final target, so the target
--   reads in later steps (keys already in the party / role tables)
--   still see the same target state as the original single statement
--   did.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_FSS_PTY_S1_SRC    source clients, deactivated parties
--                                  removed
--   Step 20  WRK_FSS_PTY_S2_DQ     name standardisation, gender, birth
--                                  date, ethnicity, race, language and
--                                  suffix checks
--   Step 30  WRK_FSS_PTY_S3_DQ2    exception details resolved from the
--                                  exception catalogue
--   Step 40  WRK_FSS_PTY_S4_ROUTED party / role keys, exception groups,
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
--   WRK_FSS_PTY_S1_SRC, WRK_FSS_PTY_S2_DQ, WRK_FSS_PTY_S3_DQ2,
--   WRK_FSS_PTY_S4_ROUTED.  They live in the same schema as the targets
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
--     DELETE of targets.  The IDQ truncate of the party and role
--     tables is NOT performed; keys already present are skipped
--     instead (uq_pty / uq_rle guards).  A re-run therefore inserts
--     nothing twice, but it also does not remove rows that IDQ would
--     have truncated away.
--   * PRESERVED: the party table's birth date is the source date of
--     birth, so a future birth date is still loaded; the language
--     exception row writes the checked birth date instead (blank for
--     a future one).
--   * PRESERVED: ethnicity, race and language exceptions are routed on
--     the looked-up code, so an unconfigured code produces no row;
--     gender is routed on the looked-up description.
--   * PRESERVED: the suffix check uses the code-value lookup WITHOUT a
--     code-type filter, exactly as in the original.
--   * PRESERVED: the commented-out testing source filter is not
--     applied, exactly as in the original.
--   * Version sequence is hard-coded to 1 and the period start date is
--     the last-update date on both targets, exactly as in the original.
--
-- INSTALL
--   Install schema is FSS_ETL_WRK in database MDM_ETL_FSS.  All table
--   names in the code below are unqualified, as in the original code.
--   Shared control calls (sp_etl_job_begin / sp_etl_checkpoint /
--   sp_etl_job_finish / sp_etl_job_fail) take SOURCE first and live in
--   the shared framework; shared helpers are fn_snow_helperNN_common.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so
--   every existing CALL still works.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty (
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
    c_source     VARCHAR DEFAULT 'FSS';
    c_workflow   VARCHAR DEFAULT 'wf_FSS_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty';
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
    DROP TABLE IF EXISTS WRK_FSS_PTY_S1_SRC;
    DROP TABLE IF EXISTS WRK_FSS_PTY_S2_DQ;
    DROP TABLE IF EXISTS WRK_FSS_PTY_S3_DQ2;
    DROP TABLE IF EXISTS WRK_FSS_PTY_S4_ROUTED;

    -- ---- Step 10: SOURCE + REMOVE DEACTIVATED ------------------------------
    -- Purpose: the active FSS clients to load -- last active
    -- registration, minus any party on the deactivation list.  Every
    -- later step reads this table, never the raw source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PTY_S1_SRC AS
    SELECT s.*
      FROM (SELECT v.SOURCE_TYPE, v.DT_LAST_UPDATE, v.PTY_SRC_KEY, v.ID_CLIENT, v.NM_FIRST, v.NM_LAST, v.NM_MIDDLE,
                   v.DT_DOB, v.CD_GENDER, v.LANGUAGE_CD, v.CD_HISPANIC, v.RACE_AN, v.RACE_ASIAN, v.RACE_AA,
                   v.RACE_WHITE, v.RACE_PI, v.CD_SUFFIX
              FROM V_FSS_ETL_SRC v
             WHERE v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y') s
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = s.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PTY_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PTY_S1_SRC', 'CREATED',
        'Active source clients: last active registration minus deactivated parties. '
        || 'Read by the checks step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: CHECKS ----------------------------------------------------
    -- Purpose: standardise names (with the source suffix), check
    -- gender, birth date, ethnicity, race indicators, language and the
    -- suffix rule.  Reads ONLY WRK_FSS_PTY_S1_SRC (plus reference
    -- lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PTY_S2_DQ AS
    WITH
    lkp_cv     AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_cv_any AS (SELECT * FROM TABLE(fn_snow_helper42_common())),
    lkp_junk   AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT a.*,
           fn_snow_helper15_common(a.NM_FIRST, a.NM_MIDDLE, a.NM_LAST,
               TRIM(NVL(a.NM_FIRST, '') || IFF(a.NM_MIDDLE IS NOT NULL, ' ' || TRIM(a.NM_MIDDLE), '')
                    || ' ' || NVL(LTRIM(a.NM_LAST), '')),
               NULL, a.CD_SUFFIX, NULL, nsx.MSTR_CODE_VALUE,
               jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)                                    AS nm,
           fn_snow_helper17_common(a.CD_GENDER, 'Indv', 'FSS')                              AS gd,
           /* VALIDATION */ fn_snow_helper16_common(a.DT_DOB, 'Indv', 'FSS', :l_run_ts)     AS birth_exception_code,
           et.MSTR_CODE_VALUE                                                               AS ethnicity_mstr,
           fn_snow_helper19_common(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
           lg.MSTR_CODE_VALUE                                                               AS language_mstr,
           sx.MSTR_CODE_VALUE                                                               AS std_suffix,
           /* VALIDATION */ fn_snow_helper20_common(a.CD_SUFFIX, sx.MSTR_CODE_VALUE)       AS suffix_exception_code
      FROM WRK_FSS_PTY_S1_SRC a
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.NM_FIRST)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.NM_LAST)) AND jl.IS_LAST_JUNK
      -- lkp_V_Lookup_Sfx_Code_Value inside the name mapplet (CODE_TYPE 'SUFFIX')
      LEFT JOIN lkp_cv nsx ON nsx.CODE_TYPE = 'SUFFIX' AND nsx.SRC_SYS = 'FSS' AND nsx.SRC_CODE_VALUE = a.CD_SUFFIX
      LEFT JOIN lkp_cv et  ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'FSS' AND et.SRC_CODE_VALUE = a.CD_HISPANIC
      LEFT JOIN lkp_cv lg  ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = 'FSS' AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD
      -- rule_Suffix_Std's lkp_V_LOOKUP_CODE_VALUE (no code-type filter)
      LEFT JOIN lkp_cv_any sx ON sx.SRC_SYS = 'FSS' AND sx.SRC_CODE_VALUE = a.CD_SUFFIX;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PTY_S2_DQ;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DQ_CHECKS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PTY_S2_DQ', 'CREATED',
        'Checked clients: standardised names, gender, birth date, ethnicity, race, language and suffix results. '
        || 'Read by the exception-catalogue step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DQ_CHECKS', :l_rows) || CHR(10);

    -- ---- Step 30: EXCEPTION CATALOGUE ---------------------------------------
    -- Purpose: flatten the check results into plain columns and resolve
    -- every exception code / description / type from the exception
    -- catalogue.  Reads ONLY WRK_FSS_PTY_S2_DQ.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PTY_S3_DQ2 AS
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
           /* BAD DATA */ IFF(d.birth_exception_code IS NULL, d.DT_DOB, NULL) AS std_birth_date,
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
           xl.EXCEPTION_TYPE                              AS language_exception_type,
           xs.EXCEPTION_DESC                              AS suffix_exception_desc,
           xs.EXCEPTION_TYPE                              AS suffix_exception_type
      FROM WRK_FSS_PTY_S2_DQ d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = d.rc:exception_code::VARCHAR
      LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language')
      LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.suffix_exception_code;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PTY_S3_DQ2;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'DQ2_EXCEPTIONS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PTY_S3_DQ2', 'CREATED',
        'One row per client with standardised values and every exception code, description and type resolved. '
        || 'Read by the router step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 DQ2_EXCEPTIONS', :l_rows) || CHR(10);

    -- ---- Step 40: ROUTE ------------------------------------------------------
    -- Purpose: build the party and role keys, put every client into its
    -- exception groups, and set the insert-only guards (first row per
    -- key in this run, key not already in the target).  This is the
    -- only table step 50 reads.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_PTY_S4_ROUTED AS
    WITH
    routed AS (
        SELECT d.*,
               TRIM(d.PTY_SRC_KEY)                                                   AS pkey_trim,
               TRIM(d.PTY_SRC_KEY) || '|' || :P_RLE_BO_CLASS_CD_MEMBER                AS rle_pkey,
               (d.gender_exception_description IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT') AS grp_gender,
               d.birth_exception_code IS NOT NULL                                    AS grp_birth,
               (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT')  AS grp_ethnicity,
               (d.race_exception_desc IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT')       AS grp_race,
               d.language_exception_code IS NOT NULL                                 AS grp_language,
               d.suffix_exception_code IS NOT NULL                                   AS grp_suffix
          FROM WRK_FSS_PTY_S3_DQ2 d
    )
    SELECT r.*,
           1 /* TIMELINE: VERSION_SEQ hard-coded */                  AS version_seq,
           1                                                          AS hub_state_ind,
           'FSS'                                                      AS src_sys,
           :l_run_ts                                                  AS run_ts,
           :c_mapping                                                 AS mapping_name,
           :P_PTY_BO_CLASS_CD_MEMBER                                  AS pty_bo_class_cd,
           :P_RLE_BO_CLASS_CD_MEMBER                                  AS rle_bo_class_cd,
           TO_VARCHAR(r.DT_DOB, 'MM/DD/YYYY')                         AS dob_text,
           'Gender'                                                   AS attr_gender,
           'Birth Date'                                               AS attr_birth,
           'Ethnicity_Cd'                                             AS attr_ethnicity,
           'Race_Cd'                                                  AS attr_race,
           'Language_Cd'                                              AS attr_language,
           'Name Suffix'                                              AS attr_suffix,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                           AS uq_pty,
           (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL)                          AS uq_rle,
           ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.ID_CLIENT, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_gender,
           ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.ID_CLIENT, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1  AS uq_birth,
           ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.ID_CLIENT,
                                           r.ethnicity_exception_type, r.ethnicity_exception_code
                                  ORDER BY r.DT_LAST_UPDATE DESC) = 1                                  AS uq_ethnicity,
           ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.ID_CLIENT, r.race_exception_type,
                                           r.race_exception_cd ORDER BY r.DT_LAST_UPDATE DESC) = 1     AS uq_race,
           ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.PTY_SRC_KEY, r.ID_CLIENT,
                                           r.language_exception_type, r.language_exception_code
                                  ORDER BY r.DT_LAST_UPDATE DESC) = 1                                  AS uq_language,
           ROW_NUMBER() OVER (PARTITION BY r.grp_suffix, r.PTY_SRC_KEY, r.ID_CLIENT, r.suffix_exception_type,
                                           r.suffix_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_suffix
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_PTY_S4_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_PTY_S4_ROUTED', 'CREATED',
        'Routed clients: party / role keys, exception groups and insert-only guards. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The eight INSERTs below are the eight branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final CTE to step 40.  A row can land in more
    -- than one branch (a valid party AND its exception rows), exactly
    -- as in INSERT ALL.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 50a. Valid party -> C_S_FSS_PTY
    INSERT INTO C_S_FSS_PTY
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, BIRTH_DT,
            SRC_FULL_NM, ETHNCTY, SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM)
    SELECT pkey_trim, DT_LAST_UPDATE, version_seq, run_ts, DT_LAST_UPDATE, pkey_trim, hub_state_ind,
           pty_bo_class_cd, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name,
           mdm_gender_code, DT_DOB, std_src_full_name, ethnicity_mstr, CD_HISPANIC, mdm_race_cd,
           src_race_ind_list, DT_LAST_UPDATE, language_mstr, std_suffix
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE uq_pty;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50b. Valid role -> C_S_FSS_PTY_RLE
    INSERT INTO C_S_FSS_PTY_RLE
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
    SELECT rle_pkey, DT_LAST_UPDATE, version_seq, run_ts, DT_LAST_UPDATE, rle_pkey, hub_state_ind, pkey_trim,
           rle_bo_class_cd, DT_LAST_UPDATE
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE uq_rle;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50c. Invalid gender -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
            LAST_NAME)
    SELECT src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
           CD_GENDER, mapping_name, PTY_SRC_KEY, ID_CLIENT, CD_GENDER, DT_DOB, run_ts, NM_FIRST, NM_MIDDLE,
           NM_LAST
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_gender AND uq_gender;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50d. Invalid birth date -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
           run_ts, mapping_name, CD_GENDER, attr_birth, ID_CLIENT, std_prfx_name, NM_FIRST, NM_LAST,
           NM_MIDDLE, dob_text, DT_DOB
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_birth AND uq_birth;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50e. Invalid ethnicity -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
            SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
            SRC_SYS_ID_2, ATTRIBUTE_VALUE)
    SELECT run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
           attr_ethnicity, CD_GENDER, PTY_SRC_KEY, src_sys, NM_FIRST, std_lst_name, std_mdl_name,
           mapping_name, DT_DOB, DT_LAST_UPDATE, ID_CLIENT, CD_HISPANIC
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_ethnicity AND uq_ethnicity;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50f. Invalid race -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
            MAPPING_NAME, ATTRIBUTE_VALUE)
    SELECT ID_CLIENT, PTY_SRC_KEY, src_sys, race_exception_cd, race_exception_desc, race_exception_type,
           run_ts, NM_FIRST, std_mdl_name, std_lst_name, CD_GENDER, DT_DOB, attr_race, std_prfx_name,
           DT_LAST_UPDATE, mapping_name, src_race_ind_list
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_race AND uq_race;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50g. Invalid language -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, PERIOD_START_DATE)
    SELECT src_sys, PTY_SRC_KEY, ID_CLIENT, language_exception_type, language_exception_code,
           language_exception_desc, run_ts, NM_FIRST, std_mdl_name, std_lst_name, std_birth_date,
           CD_GENDER, attr_language, LANGUAGE_CD, mapping_name, DT_LAST_UPDATE
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_language AND uq_language;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50h. Invalid suffix -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, ALIAS_SUFFIX, BIRTH_DATE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, MAPPING_NAME)
    SELECT src_sys, PTY_SRC_KEY, ID_CLIENT, suffix_exception_type, suffix_exception_code,
           suffix_exception_desc, run_ts, NM_FIRST, NM_MIDDLE, NM_LAST, CD_SUFFIX, std_suffix, DT_DOB,
           attr_suffix, CD_SUFFIX, mapping_name
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_suffix AND uq_suffix;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_FSS_PTY, C_S_FSS_PTY_RLE, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid parties, valid roles and all demographic exception rows. '
        || 'Count shown is the total rows inserted by all eight INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_FSS_Pty completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_FSS_Pty failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
