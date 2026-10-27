-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TTF_Pty  --  MODULAR REWRITE (simplified v2 style)
--
-- IDQ mapping: m_Tgt_C_S_TTF_Pty, workflow wf_TTF_Stage_Load
-- (second mapping in the workflow run order, after Pty_Validation).
--
-- Business flow, in plain words: load the active TTF clients into the
-- party and party-role tables, and log demographic exceptions.  Active
-- means the party is not in the inactive-status table maintained by
-- Pty_Validation.  Gender comes from SEXID (33 -> F, 34 -> M, else U);
-- ethnicity is '55' when RACEETHNICITYID = '55'.  Names are
-- standardised, and gender, birth date, ethnicity and race are
-- validated against master data.  An exception never rejects a client:
-- the client is loaded AND logged, and a future birth date is loaded
-- as NULL.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (active -> dq ->
--   dq2 -> routed -> final), one transaction, one log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE transaction,
--   so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TTF_PTY_S1_ACTIVE  active clients only (inactive
--                                   parties filtered out) + gender and
--                                   ethnicity expressions
--   Step 20  WRK_TTF_PTY_S2_DQ      standardise names + validate gender,
--                                   birth date, ethnicity, race
--   Step 30  WRK_TTF_PTY_S3_DQ2     standardised fields + exception
--                                   descriptions and types pulled out
--   Step 40  WRK_TTF_PTY_S4_ROUTED  party / role keys, exception groups,
--                                   constants, and insert-only guards
--   Step 50  PUBLISH               targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_TTF_PTY_S1_ACTIVE, WRK_TTF_PTY_S2_DQ, WRK_TTF_PTY_S3_DQ2,
--   WRK_TTF_PTY_S4_ROUTED.
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
--     of C_S_TTF_PTY and C_S_TTF_PTY_RLE is NOT performed; keys already
--     present are skipped by the uq_pty / uq_rle guards instead.
--   * PRESERVED: the Invalid_Language / Invalid_Suffix router groups
--     test ports that are not fed in IDQ and have no target, so they
--     never write -- no such branches are generated here either.
--   * PRESERVED: PRFRD_LANG_CD and SFX_NM are NULL (linked to unfed
--     ports in IDQ).
--   * PRESERVED: VERSION_SEQ is hard-coded to 1; party PERIOD_START_DATE
--     is the run start (so it changes on every run), role
--     PERIOD_START_DATE is SUBMITDATE.
--   * PRESERVED: every exception class writes one EXC_STG_BAD_REC_MEMB
--     row for every row (no source-table condition in TTF), and an
--     exception never stops the party / role loading.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty (
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
    c_source     VARCHAR DEFAULT 'TTF';
    c_workflow   VARCHAR DEFAULT 'wf_TTF_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty';
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
    DROP TABLE IF EXISTS WRK_TTF_PTY_S1_ACTIVE;
    DROP TABLE IF EXISTS WRK_TTF_PTY_S2_DQ;
    DROP TABLE IF EXISTS WRK_TTF_PTY_S3_DQ2;
    DROP TABLE IF EXISTS WRK_TTF_PTY_S4_ROUTED;

    -- ---- Step 10: ACTIVE CLIENTS ----------------------------------------
    -- Purpose: the clients that may load at all -- every TTF client
    -- whose party key is NOT in the inactive-status table with a status
    -- set (that table is maintained by Pty_Validation, which runs
    -- first).  Gender is decoded from SEXID and the ethnicity flag is
    -- derived here, exactly as in the original expression.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PTY_S1_ACTIVE AS
    SELECT v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.SUBMITDATE, v.SEXID,
           v.RACEETHNICITYID, v.PTY_SRC_KEY, v.LOAD_DATE,
           DECODE(v.SEXID, '33', 'F', '34', 'M', 'U')            AS gender,
           IFF(v.RACEETHNICITYID = '55', '55', NULL)             AS ethnicity
      FROM V_TTF_ETL_SRC v
     WHERE NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PTY_S1_ACTIVE;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PTY_S1_ACTIVE', 'CREATED',
        'Active clients only: inactive parties filtered out, gender decoded from SEXID, ethnicity flag derived. '
        || 'Read by the DQ step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: STANDARDISE + VALIDATE --------------------------------
    -- Purpose: attach the name-standardisation object, the gender
    -- object, the birth-date exception code, and the looked-up
    -- ethnicity / race master codes to every active client.  This is
    -- the DQ heart of the mapping; it reads ONLY step 10 (plus the
    -- reference lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PTY_S2_DQ AS
    WITH
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT a.*,
           fn_snow_helper15_common(a.FIRSTNAME, a.MIDDLENAME, a.LASTNAME,
               TRIM(NVL(a.FIRSTNAME, '') || IFF(a.MIDDLENAME IS NOT NULL, ' ' || TRIM(a.MIDDLENAME), '')
                    || ' ' || NVL(LTRIM(a.LASTNAME), '')),
               NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)        AS nm,
           fn_snow_helper17_common(a.gender, 'Indv', 'TTF')                            AS gd,
           /* VALIDATION */ fn_snow_helper16_common(a.DOB, 'Indv', 'TTF', :l_run_ts)  AS birth_exception_code,
           et.MSTR_CODE_VALUE                                                          AS ethnicity_mstr,
           rc.MSTR_CODE_VALUE                                                          AS race_mstr
      FROM WRK_TTF_PTY_S1_ACTIVE a
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRSTNAME)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LASTNAME)) AND jl.IS_LAST_JUNK
      LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'TTF' AND et.SRC_CODE_VALUE = a.ethnicity
      LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'TTF' AND rc.SRC_CODE_VALUE = a.RACEETHNICITYID;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PTY_S2_DQ;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DQ', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PTY_S2_DQ', 'CREATED',
        'Name-standardisation and gender objects attached, birth-date exception code computed, '
        || 'ethnicity and race master codes looked up. Read by the field-extraction step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DQ', :l_rows) || CHR(10);

    -- ---- Step 30: FIELD EXTRACTION --------------------------------------
    -- Purpose: pull the standardised name fields, the MDM gender code,
    -- and every exception code / description / type out of the step-20
    -- objects, and null out a future birth date (it is logged, not
    -- loaded, as a date).  Reads ONLY step 20 (plus the exception
    -- lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PTY_S3_DQ2 AS
    WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
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
           xr.EXCEPTION_CODE                 AS race_exception_code,
           xr.EXCEPTION_DESC                 AS race_exception_desc,
           xr.EXCEPTION_TYPE                 AS race_exception_type
      FROM WRK_TTF_PTY_S2_DQ d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race');
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PTY_S3_DQ2;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'DQ2', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PTY_S3_DQ2', 'CREATED',
        'Standardised name fields, MDM gender code, and gender / birth-date / ethnicity / race exception '
        || 'codes with descriptions and types. Read by the router step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 DQ2', :l_rows) || CHR(10);

    -- ---- Step 40: ROUTER + GUARDS ---------------------------------------
    -- Purpose: the publish-ready rows.  Party and role keys are built,
    -- each row is placed in its exception groups (gender, birth date,
    -- ethnicity, race -- a row can be in several at once, and an
    -- exception never stops the party loading), constants are attached,
    -- and the insert-only guards are computed: uq_pty / uq_rle skip keys
    -- already in the party / role targets (first row per key in this
    -- run wins), and uq_gender / uq_birth / uq_ethnicity / uq_race keep
    -- one exception row per key per class.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_PTY_S4_ROUTED AS
    WITH
    routed AS (
        SELECT d.*,
               TRIM(d.PTY_SRC_KEY)                                        AS pkey_trim,
               TRIM(d.PTY_SRC_KEY) || '|' || :P_RLE_BO_CLASS_CD_MEMBER     AS rle_pkey,
               d.gender_exception_description IS NOT NULL                 AS grp_gender,
               d.birth_exception_code IS NOT NULL                         AS grp_birth,
               d.ethnicity_exception_code IS NOT NULL                     AS grp_ethnicity,
               d.race_exception_desc IS NOT NULL                          AS grp_race
          FROM WRK_TTF_PTY_S3_DQ2 d
    )
    SELECT r.*,
           1 /* TIMELINE: VERSION_SEQ hard-coded */         AS version_seq,
           1                                                 AS hub_state_ind,
           'TTF'                                             AS src_sys,
           :l_run_ts                                         AS run_ts,
           :c_mapping                                        AS mapping_name,
           :P_PTY_BO_CLASS_CD_MEMBER                         AS pty_bo_class_cd,
           :P_RLE_BO_CLASS_CD_MEMBER                         AS rle_bo_class_cd,
           TO_VARCHAR(r.DOB, 'MM/DD/YYYY')                   AS dob_text,
           'Gender'                                          AS attr_gender,
           'Birth Date'                                      AS attr_birth,
           'Ethnicity_Cd'                                    AS attr_ethnicity,
           'Race_Cd'                                         AS attr_race,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                  AS uq_pty,
           (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL)                 AS uq_rle,
           ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.CLIENTS_ID, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.SUBMITDATE DESC) = 1 AS uq_gender,
           ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.CLIENTS_ID, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.SUBMITDATE DESC) = 1  AS uq_birth,
           ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.CLIENTS_ID,
                                           r.ethnicity_exception_type, r.ethnicity_exception_code
                                  ORDER BY r.SUBMITDATE DESC) = 1                                  AS uq_ethnicity,
           ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.CLIENTS_ID, r.race_exception_type,
                                           r.race_exception_code ORDER BY r.SUBMITDATE DESC) = 1   AS uq_race
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_PTY_S4_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_PTY_S4_ROUTED', 'CREATED',
        'Publish-ready rows: party / role keys, exception groups, constants, and insert-only guards '
        || 'uq_pty / uq_rle / uq_gender / uq_birth / uq_ethnicity / uq_race. Published in step 50.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning.  The six INSERTs below are the
    -- six branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHERE conditions -- only the
    -- source changed, from the final SELECT to step 40.
    BEGIN TRANSACTION;
    -- 50a. Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_TTF_PTY
    INSERT INTO C_S_TTF_PTY
           (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, HUB_STATE_IND,
            PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, SRC_FULL_NM, ETHNCTY,
            SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM, PERIOD_START_DATE,
            BIRTH_DT)
    SELECT pkey_trim, version_seq, run_ts, SUBMITDATE, pkey_trim, hub_state_ind, pty_bo_class_cd,
           std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name, mdm_gender_code,
           std_src_full_name, ethnicity_mstr, ethnicity, race_mstr, RACEETHNICITYID, SUBMITDATE, NULL, NULL,
           run_ts, std_birth_date
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE uq_pty;
    l_rows := SQLROWCOUNT;
    -- 50b. Rtr_Exception.Valid_Party -> Write_C_S_TTF_PTY_RLE
    INSERT INTO C_S_TTF_PTY_RLE
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
    SELECT rle_pkey, SUBMITDATE, version_seq, run_ts, SUBMITDATE, rle_pkey, hub_state_ind, pkey_trim,
           rle_bo_class_cd, SUBMITDATE
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE uq_rle;
    l_rows := :l_rows + SQLROWCOUNT;
    -- 50c. Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
            LAST_NAME)
    SELECT src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
           gender, mapping_name, PTY_SRC_KEY, CLIENTS_ID, gender, DOB, run_ts, FIRSTNAME, MIDDLENAME,
           LASTNAME
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE grp_gender AND uq_gender;
    l_rows := :l_rows + SQLROWCOUNT;
    -- 50d. Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
           run_ts, mapping_name, gender, attr_birth, CLIENTS_ID, std_prfx_name, FIRSTNAME, LASTNAME,
           MIDDLENAME, dob_text, DOB
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE grp_birth AND uq_birth;
    l_rows := :l_rows + SQLROWCOUNT;
    -- 50e. Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
            SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
            SRC_SYS_ID_2, ATTRIBUTE_VALUE)
    SELECT run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
           attr_ethnicity, gender, PTY_SRC_KEY, src_sys, FIRSTNAME, std_lst_name, std_mdl_name,
           mapping_name, DOB, SUBMITDATE, CLIENTS_ID, ethnicity
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE grp_ethnicity AND uq_ethnicity;
    l_rows := :l_rows + SQLROWCOUNT;
    -- 50f. Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
            MAPPING_NAME, ATTRIBUTE_VALUE)
    SELECT CLIENTS_ID, PTY_SRC_KEY, src_sys, race_exception_code, race_exception_desc, race_exception_type,
           run_ts, FIRSTNAME, std_mdl_name, std_lst_name, gender, DOB, attr_race, std_prfx_name, SUBMITDATE,
           mapping_name, RACEETHNICITYID
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE grp_race AND uq_race;
    l_rows := :l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_TTF_PTY, C_S_TTF_PTY_RLE, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid parties, valid roles, and gender / birth-date / ethnicity / race '
        || 'exceptions. Count shown is total rows inserted across all six inserts.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (total inserted)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TTF_Pty completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TTF_Pty failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
