-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing  --  MODULAR REWRITE (template proc)
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-09  Build the valid-member list for today.
--   BR-10  Rebuild STG_TRS_VALID_MEMBERS; downstream mappings join to it.
--   BR-13  A party needs a usable first OR last name to load.
--   BR-14  Gender / death-date problems are logged but NEVER reject a party.
--   BR-15/16/17/18/19  Standardise names; validate gender, birth date
--          (future = exception), death date (future = exception),
--          race and ethnicity against master data.
--   BR-12  One row per party key and per role key (last row wins).
--   BR-02  Every failing class goes to EXC_STG_BAD_REC_MEMB; the load
--          does not fail because of bad rows.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (new_valid_indvs
--   -> all_indv -> src -> dq -> base -> router -> dedup -> both_kinds),
--   one transaction, one log line at the end.  If it failed, nothing
--   told you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE transaction,
--   so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_PTY_S1_SRC    source + valid-member list (BR-09)
--   Step 20  WRK_TRS_PTY_S2_DQ     standardise + validate every person (BR-15..19)
--   Step 30  WRK_TRS_PTY_S3_ROUTER router rows: the exception classes (BR-13/14)
--   Step 40  WRK_TRS_PTY_S4_DEDUP  valid rows, de-duplicated + ranked (BR-12)
--            (branch: step 40 reads step 20, NOT step 30 -- exceptions and
--             valid rows are two branches of the same DQ output)
--   Step 50  PUBLISH              targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_PTY_S1_SRC, WRK_TRS_PTY_S2_DQ, WRK_TRS_PTY_S3_ROUTER,
--   WRK_TRS_PTY_S4_DEDUP.  They live in the same schema as the targets
--   (unqualified names, as in the original code), are prefixed WRK_TRS_,
--   and are registered in JOB_CONTROL_ETL at creation.
--   They survive a session crash (TRANSIENT, not TEMP), which is what
--   makes inspection after a run possible; a pure session TEMP table would vanish with
--   the session.  A Snowflake CURSOR
--   was NOT used: cursors process row by row, and every step here is
--   set-based by design -- the work table IS the result set, held as a
--   table instead of in memory, so it can be counted and inspected after the run.  (See the User Guide, "Why work tables, not cursors".)
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  IDQ truncates C_S_TRS_PTY / C_S_TRS_PTY_RLE;
--     the Snowflake version instead skips keys already present
--     (uq_pty / uq_rle / uq_exc_* guards).  A re-run therefore inserts
--     nothing twice, but it also does not remove rows that IDQ would
--     have truncated away -- see the User Guide, "Parity gaps".
--   * The stored source filter INDV_ID = 504937068 is NOT applied here,
--     exactly as in the original Snowflake code (it was not part of the
--     custom query).  Confirm in the live IDQ mapping whether it should
--     be (BR notes, Verify item 1).
--   * VERSION_SEQ is hard-coded to 1 (TIMELINE: the MD5 / version
--     comparison is commented out in IDQ); PERIOD_END_DATE,
--     PERIOD_REFERENCE_TIME and TIMELINE_ACTION are NULL (unfed ports).
--   * HUB_STATE_IND, UPDATED_BY, CREATE_DATE, CREATOR, FLAG_SRC and
--     ROWID_OBJECT / DELETED_* are NULL (unfed ports), as in the original.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',
    P_DC_INDV_TBL_SRC        VARCHAR DEFAULT 'DC_INDV',
    P_MCI_TBL_SRC            VARCHAR DEFAULT 'MCI',
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
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
            'TRS_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_TRS_PTY_S1_SRC;
    DROP TABLE IF EXISTS WRK_TRS_PTY_S2_DQ;
    DROP TABLE IF EXISTS WRK_TRS_PTY_S3_ROUTER;
    DROP TABLE IF EXISTS WRK_TRS_PTY_S4_DEDUP;


    -- ---- Step 10: SOURCE + VALID-MEMBER LIST (BR-09) --------------------
    -- Purpose: the "who is valid today" snapshot.  Conversion records,
    -- cleared + active DC individuals, active MCI individuals and the
    -- previously valid members, MINUS today's inactivations/deletions
    -- and MINUS anyone already in the deactivation log (re-runs /
    -- re-activations).  Every later step reads this table, never the
    -- raw sources again, so a re-run of a later step sees the same
    -- snapshot as the first run.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PTY_S1_SRC AS
    WITH
    new_valid_indvs AS (
        SELECT DISTINCT indv_id FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA WHERE conversion_ind = 'C'
        UNION
        SELECT DISTINCT indv_id FROM STG_TRS_D_DC_INDV
         WHERE FILE_CLEARANCE_SW = 'Y' AND Inactive_ind = 'N' AND delete_sw = 'N'
        UNION
        SELECT DISTINCT indv_id FROM STG_TRS_D_CV_DC_MCI_INDV WHERE Inactive_ind = 'N'
        UNION
        SELECT DISTINCT indv_id FROM STG_TRS_VALID_MEMBERS
        MINUS
        SELECT DISTINCT indv_id FROM STG_TRS_D_DC_INDV WHERE Inactive_ind = 'Y' OR delete_sw = 'Y'
        MINUS
        SELECT DISTINCT indv_id FROM STG_TRS_D_CV_DC_MCI_INDV WHERE Inactive_ind = 'Y'
        MINUS
        SELECT indv_id FROM STG_TRS_DEACTIVED_MEMBERS
    ),
    all_indv AS (
        SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
               NULL AS SSA_VAL_SW, NULL AS FILE_CL_SW, DOB_DT, NULL AS DEATH_DT, CREATE_DT,
               :P_MCI_TBL_SRC AS SRC_TBL
          FROM STG_TRS_D_CV_DC_MCI_INDV
        UNION ALL
        SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
               SSA_VALIDATION_SW, FILE_CLEARANCE_SW, DOB_DT, DEATH_DT, CREATE_DT, :P_DC_INDV_TBL_SRC
          FROM STG_TRS_D_DC_INDV
    )
    SELECT DISTINCT a.INDV_ID, RTRIM(LTRIM(a.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(a.MID_NAME)) AS MID_NAME,
           RTRIM(LTRIM(a.LAST_NAME)) AS LAST_NAME, RTRIM(a.SUFX_NAME) AS SUFX_NAME,
           RTRIM(a.PREFIX_NAME) AS PREFIX_NAME, a.GENDER_CD, a.RACE_CD, a.ETHNICITY_CD, a.SSA_VAL_SW,
           a.FILE_CL_SW, a.DOB_DT, a.CREATE_DT, a.SRC_TBL, a.DEATH_DT
      FROM all_indv a
     INNER JOIN new_valid_indvs f ON f.indv_id = a.indv_id;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PTY_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_VALID_LIST', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PTY_S1_SRC', 'CREATED',
        'Valid-member snapshot for today: source individuals joined to the valid list (BR-09). '
        || 'Read by the DQ step; never re-read the raw sources after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_VALID_LIST', :l_rows) || CHR(10);

    -- ---- Step 20: STANDARDISE + VALIDATE (BR-15..19) --------------------
    -- Purpose: one standardised, validated row per source person, with
    -- every exception code/description resolved from EXC_LOOKUP_CODE_VALUE.
    -- This is the DQ heart of the mapping: name standardisation (prefix /
    -- suffix, junk names), gender, birth date, race, ethnicity, death date.
    -- It reads ONLY WRK_TRS_PTY_S1_SRC (plus the reference lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PTY_S2_DQ AS
    WITH
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    dq AS (
        SELECT s.*,
               IFF(s.SRC_TBL = :P_DC_INDV_TBL_SRC, TO_VARCHAR(s.INDV_ID) || '|' || :P_DC_INDV_TBL_SRC,
                   TO_VARCHAR(s.INDV_ID))                                                     AS pkey_src_object,
               TRIM(NVL(s.FIRST_NAME, '') || IFF(s.MID_NAME IS NOT NULL, ' ' || TRIM(s.MID_NAME), '')
                    || ' ' || NVL(LTRIM(s.LAST_NAME), ''))                                    AS src_full_name,
               fn_snow_helper15_common(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME,
                   TRIM(NVL(s.FIRST_NAME, '') || IFF(s.MID_NAME IS NOT NULL, ' ' || TRIM(s.MID_NAME), '')
                        || ' ' || NVL(LTRIM(s.LAST_NAME), '')),
                   s.PREFIX_NAME, s.SUFX_NAME, pfx.MSTR_CODE_VALUE, sfx.MSTR_CODE_VALUE,
                   jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)                                  AS nm,
               fn_snow_helper17_common(s.GENDER_CD, 'Indv', 'TRS')                            AS gd,
               fn_snow_helper16_common(s.DOB_DT, 'Indv', 'TRS', :l_run_ts)                    AS birth_exception_code,
               rc.MSTR_CODE_VALUE                                                             AS race_mstr,
               et.MSTR_CODE_VALUE                                                             AS ethnicity_mstr,
               IFF(s.DEATH_DT > :l_run_ts, 'Invalid_Death_Date', NULL)                        AS death_exception_code
          FROM WRK_TRS_PTY_S1_SRC s
          LEFT JOIN lkp_cv pfx ON pfx.CODE_TYPE = 'PREFIX' AND pfx.SRC_SYS = 'TRS' AND pfx.SRC_CODE_VALUE = s.PREFIX_NAME
          LEFT JOIN lkp_cv sfx ON sfx.CODE_TYPE = 'SUFFIX' AND sfx.SRC_SYS = 'TRS' AND sfx.SRC_CODE_VALUE = s.SUFX_NAME
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(s.FIRST_NAME)) AND jf.IS_FIRST_JUNK
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(s.LAST_NAME)) AND jl.IS_LAST_JUNK
          LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'TRS' AND rc.SRC_CODE_VALUE = s.RACE_CD
          LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'TRS' AND et.SRC_CODE_VALUE = s.ETHNICITY_CD
    )
    SELECT d.*,
           TRIM(d.pkey_src_object)               AS pkey_trim,
           d.nm:first_name::VARCHAR              AS std_first_name,
           d.nm:middle_name::VARCHAR             AS std_mdl_name,
           d.nm:last_name::VARCHAR               AS std_lst_name,
           d.nm:full_name::VARCHAR               AS std_full_name,
           d.nm:prfx_name::VARCHAR               AS std_prfx_name,
           d.nm:sfx_name::VARCHAR                AS std_sfx_name,
           d.gd:mdm_gender_code::VARCHAR         AS mdm_gender_code,
           d.gd:exception_code::VARCHAR          AS gender_exception_code,
           xg.EXCEPTION_DESC                     AS gender_exception_description,
           xg.EXCEPTION_TYPE                     AS gender_exception_type,
           IFF(d.birth_exception_code IS NULL, d.DOB_DT, NULL) AS std_birth_date,
           xb.EXCEPTION_DESC                     AS birth_exception_description,
           xb.EXCEPTION_TYPE                     AS birth_exception_type,
           xr.EXCEPTION_CODE                     AS race_exception_code,
           xr.EXCEPTION_DESC                     AS race_exception_desc,
           xr.EXCEPTION_TYPE                     AS race_exception_type,
           xe.EXCEPTION_CODE                     AS ethnicity_exception_code,
           xe.EXCEPTION_DESC                     AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE                     AS ethnicity_exception_type,
           xd.EXCEPTION_CODE                     AS death_exception_lkp_code,
           xd.EXCEPTION_DESC                     AS death_exception_desc,
           xd.EXCEPTION_TYPE                     AS death_exception_type,
           (fn_snow_helper03_common(d.nm:first_name::VARCHAR)
            OR fn_snow_helper03_common(d.nm:last_name::VARCHAR)) AS name_missing
      FROM dq d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = d.death_exception_code;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PTY_S2_DQ;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DQ_STANDARDISE_VALIDATE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PTY_S2_DQ', 'CREATED',
        'One standardised, validated row per source person, with exception codes resolved (BR-15..19). '
        || 'Read by both the router step and the dedup step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DQ', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTER -- exception classes (BR-13/14) -----------------
    -- Purpose: the rows that will become exception records.  Note the
    -- business rule that makes this step subtle: a row can appear in
    -- MORE than one exception class (IDQ router groups are not exclusive),
    -- and gender / death-date exceptions do NOT stop the party loading
    -- in step 40 -- they are logged here AND loaded there.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PTY_S3_ROUTER AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    router AS (
        SELECT b.*,
               CASE WHEN fn_snow_helper03_common(b.std_first_name) THEN 'Missing_First_Name'
                    WHEN fn_snow_helper03_common(b.std_lst_name) THEN 'Missing_Last_Name' END  AS name_exception_code,
               CASE WHEN fn_snow_helper03_common(b.std_first_name) THEN 'First Name'
                    WHEN fn_snow_helper03_common(b.std_lst_name) THEN 'Last Name' END          AS name_attribute_name,
               CASE WHEN fn_snow_helper03_common(b.std_first_name) THEN b.std_first_name
                    WHEN fn_snow_helper03_common(b.std_lst_name) THEN b.std_lst_name END       AS name_attribute_value
          FROM WRK_TRS_PTY_S2_DQ b
    )
    SELECT r.*,
           xn.EXCEPTION_TYPE AS name_exception_type,
           xn.EXCEPTION_DESC AS name_exception_desc,
           ROW_NUMBER() OVER (PARTITION BY r.name_missing, r.pkey_src_object, xn.EXCEPTION_TYPE,
                                           r.name_exception_code ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_name,
           ROW_NUMBER() OVER (PARTITION BY r.gender_exception_description IS NOT NULL, r.pkey_src_object,
                                           r.gender_exception_type, r.gender_exception_code
                                  ORDER BY r.CREATE_DT DESC) = 1                                 AS uq_exc_gender,
           ROW_NUMBER() OVER (PARTITION BY r.death_exception_desc IS NOT NULL, r.pkey_src_object,
                                           r.death_exception_type, r.death_exception_lkp_code
                                  ORDER BY r.CREATE_DT DESC) = 1                                 AS uq_exc_death,
           ROW_NUMBER() OVER (PARTITION BY r.birth_exception_code IS NOT NULL, r.pkey_src_object,
                                           r.birth_exception_type, r.birth_exception_code
                                  ORDER BY r.CREATE_DT DESC) = 1                                 AS uq_exc_birth
      FROM router r
      LEFT JOIN lkp_exc xn ON xn.EXCEPTION_CODE = r.name_exception_code;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PTY_S3_ROUTER;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTER_EXCEPTIONS', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_TRS_PTY_S3_ROUTER', 'CREATED',
        'Router rows: name / gender / death-date / birth-date exception candidates, '
        || 'with first-row-per-exception-key flags (uq_exc_*). Published in step 50; '
        || 'gender and death-date rows are logged AND still loaded as parties (BR-14).',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTER', :l_rows) || CHR(10);

    -- ---- Step 40: DEDUP + RANK -- valid rows (BR-12) ---------------------
    -- Purpose: valid parties only (first OR last name present), distinct,
    -- one row per party key (last row in sorter order wins), flagged with
    -- whether the key is already a valid member and whether it is already
    -- in the party / role targets (the insert-only guards), plus the
    -- race / ethnicity exception flags.  Reads step 20, not step 30.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PTY_S4_DEDUP AS
    WITH
    dedup AS (
        SELECT DISTINCT pkey_trim, CREATE_DT, INDV_ID, SRC_TBL, mdm_gender_code, std_sfx_name, std_first_name,
               std_prfx_name, std_lst_name, std_mdl_name, std_birth_date, std_full_name, DEATH_DT, src_full_name,
               RACE_CD, race_mstr, race_exception_code, race_exception_desc, race_exception_type, ETHNICITY_CD,
               ethnicity_mstr, ethnicity_exception_code, ethnicity_exception_desc, ethnicity_exception_type
          FROM WRK_TRS_PTY_S2_DQ
         WHERE std_first_name IS NOT NULL OR std_lst_name IS NOT NULL
    )
    SELECT x.*,
           ROW_NUMBER() OVER (PARTITION BY x.pkey_trim
                              ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID DESC NULLS FIRST,
                                       x.SRC_TBL DESC NULLS FIRST, x.mdm_gender_code DESC NULLS FIRST,
                                       x.std_sfx_name DESC NULLS FIRST, x.std_first_name DESC NULLS FIRST,
                                       x.std_prfx_name DESC NULLS FIRST, x.std_lst_name DESC NULLS FIRST,
                                       x.std_mdl_name DESC NULLS FIRST, x.std_birth_date DESC NULLS FIRST,
                                       x.std_full_name DESC NULLS FIRST)               AS rn_pty,
           vm.PTY_PK IS NOT NULL                                                       AS is_valid_member,
           xp.PKEY_SRC_OBJECT IS NULL                                                  AS uq_pty,
           xr2.PKEY_SRC_OBJECT IS NULL                                                 AS uq_rle,
           ROW_NUMBER() OVER (PARTITION BY x.race_exception_code IS NOT NULL, x.pkey_trim,
                                           x.race_exception_type, x.race_exception_code
                                  ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID) = 1       AS uq_exc_race,
           ROW_NUMBER() OVER (PARTITION BY x.ethnicity_exception_code IS NOT NULL, x.pkey_trim,
                                           x.ethnicity_exception_type, x.ethnicity_exception_code
                                  ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID) = 1       AS uq_exc_ethnicity
      FROM dedup x
      LEFT JOIN (SELECT DISTINCT PTY_PK FROM STG_TRS_VALID_MEMBERS) vm ON vm.PTY_PK = x.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = x.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = x.pkey_trim || '|' || :P_RLE_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PTY_S4_DEDUP;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'DEDUP_VALID', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PTY_S4_DEDUP', 'CREATED',
        'Valid, de-duplicated parties (rn_pty = 1 is the row that loads), with '
        || 'is_valid_member and insert-only guards uq_pty / uq_rle / uq_exc_race / uq_exc_ethnicity (BR-12).',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 DEDUP', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The nine INSERTs below are the nine branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the both_kinds CTE to steps 30 / 40.
    BEGIN TRANSACTION;
    -- 50a. Invalid_Party_Name -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, SRC_SYS, DEATH_DT, MAPPING_NAME, MIDDLE_NAME, LAST_NAME, FIRST_NAME,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, RUN_DATE, EXCEPTION_CODE, SRC_SYS_ID_1, EXCEPTION_TYPE,
            EXCEPTION_DESC)
    SELECT CREATE_DT, 'TRS', DEATH_DT, :c_mapping, std_mdl_name, std_lst_name, std_first_name,
           name_attribute_name, name_attribute_value, :l_run_ts, name_exception_code, pkey_src_object,
           name_exception_type, name_exception_desc
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE name_missing AND uq_exc_name;
    -- 50b. Invalid_Gender_Code -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (GENDER, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC,
            EXCEPTION_TYPE, BIRTH_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, ATTRIBUTE_VALUE,
            DEATH_DT, RUN_DATE, SRC_SYS_ID_1)
    SELECT GENDER_CD, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, 'TRS',
           gender_exception_code, gender_exception_description, gender_exception_type, std_birth_date,
           'Gender', :c_mapping, CREATE_DT, GENDER_CD, DEATH_DT, :l_run_ts, pkey_src_object
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE gender_exception_description IS NOT NULL AND uq_exc_gender;
    -- 50c. Invalid_Death_Date -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, GENDER, BIRTH_DATE, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE, DEATH_DT, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, PERIOD_START_DATE,
            RUN_DATE, SRC_SYS_ID_1)
    SELECT 'TRS', std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, GENDER_CD,
           std_birth_date, death_exception_lkp_code, death_exception_desc, death_exception_type, DEATH_DT,
           TO_VARCHAR(DEATH_DT, 'MM/DD/YYYY HH24:MI:SS'), 'Death Date', CREATE_DT, :l_run_ts, pkey_src_object
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE death_exception_desc IS NOT NULL AND uq_exc_death;
    -- 50d. Invalid_BirthDate -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, RUN_DATE, PREFIX, EXCEPTION_CODE, EXCEPTION_TYPE,
            EXCEPTION_DESC, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, DEATH_DT,
            ATTRIBUTE_VALUE, SRC_SYS_ID_1)
    SELECT 'TRS', std_first_name, std_mdl_name, std_lst_name, std_sfx_name, :l_run_ts, std_prfx_name,
           birth_exception_code, birth_exception_type, birth_exception_description, std_birth_date,
           GENDER_CD, 'Birth Date', :c_mapping, CREATE_DT, DEATH_DT, TO_VARCHAR(DOB_DT, 'MM/DD/YYYY'), pkey_src_object
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE birth_exception_code IS NOT NULL AND uq_exc_birth;
    -- 50e. Valid parties -> C_S_TRS_PTY (last row per party key)
    INSERT INTO C_S_TRS_PTY
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, GNDR_CD, SFX_NM,
            PTY_BO_CLASS_CD, FRST_NM, PRFX_NM, LST_NM, MDL_NM, FULL_NM, BIRTH_DT, VERSION_SEQ,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
            HUB_STATE_IND, FLAG_SRC, DEATH_DT, SRC_FULL_NM, PERIOD_START_DATE, PERIOD_END_DATE, SRC_LAST_UPD_DT,
            SRC_ROWID, RACE_CD, ETHNCTY, SRC_ETHNCTY, SRC_RACE_CD)
    SELECT pkey_trim, NULL, NULL, NULL, NULL, mdm_gender_code, std_sfx_name, :P_PTY_BO_CLASS_CD_MEMBER,
           std_first_name, std_prfx_name, std_lst_name, std_mdl_name, std_full_name, std_birth_date,
           1, NULL, NULL, :l_run_ts, NULL, NULL, NULL, NULL, NULL, DEATH_DT, src_full_name,
           CREATE_DT, NULL, CREATE_DT, pkey_trim, race_mstr, ethnicity_mstr, ETHNICITY_CD, RACE_CD
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE rn_pty = 1 AND uq_pty;
    -- 50f. Valid roles -> C_S_TRS_PTY_RLE (last row per role key)
    INSERT INTO C_S_TRS_PTY_RLE
           (PTY_FK, PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, RLE_BO_CLASS_CD,
            VERSION_SEQ, PERIOD_END_DATE, PERIOD_START_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, UPDATED_BY,
            CREATE_DATE, CREATOR, SRC_LAST_UPD_DT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE)
    SELECT pkey_trim, pkey_trim || '|' || :P_RLE_BO_CLASS_CD_MEMBER, NULL, NULL, NULL, NULL,
           :P_RLE_BO_CLASS_CD_MEMBER, 1, NULL, CREATE_DT, NULL,
           NULL, NULL, NULL, NULL, CREATE_DT, NULL, pkey_trim || '|' || :P_RLE_BO_CLASS_CD_MEMBER, :l_run_ts
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE rn_pty = 1 AND uq_rle;
    -- 50g. New valid members -> STG_TRS_VALID_MEMBERS
    INSERT INTO STG_TRS_VALID_MEMBERS (SRC_TBL, PTY_PK, INDV_ID, CREATE_DATE)
    SELECT SRC_TBL, pkey_trim, INDV_ID, :l_run_ts
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE rn_pty = 1 AND NOT is_valid_member;
    -- 50h. Race exceptions -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, DEATH_DT, GENDER, BIRTH_DATE, MIDDLE_NAME, LAST_NAME, PREFIX, FIRST_NAME, SUFFIX,
            PERIOD_START_DATE, RUN_DATE, MAPPING_NAME)
    SELECT 'TRS', pkey_trim, race_exception_type, race_exception_desc, race_exception_code, 'Race_Cd',
           race_mstr, DEATH_DT, mdm_gender_code, std_birth_date, std_mdl_name, std_lst_name, std_prfx_name,
           std_first_name, std_sfx_name, CREATE_DT, :l_run_ts, :c_mapping
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE race_exception_code IS NOT NULL AND uq_exc_race;
    -- 50i. Ethnicity exceptions -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, PERIOD_START_DATE, DEATH_DT, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, PREFIX, LAST_NAME, MIDDLE_NAME, FIRST_NAME, SUFFIX, GENDER,
            MAPPING_NAME)
    SELECT 'TRS', pkey_trim, 'Ethnicity_Cd', ethnicity_mstr, CREATE_DT, DEATH_DT, ethnicity_exception_code,
           ethnicity_exception_desc, ethnicity_exception_type, :l_run_ts, std_prfx_name, std_lst_name,
           std_mdl_name, std_first_name, std_sfx_name, mdm_gender_code, :c_mapping
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE ethnicity_exception_code IS NOT NULL AND uq_exc_ethnicity;
    COMMIT;
    -- Publish row counts are read from the targets by difference is
    -- fragile; instead, report the work-table counts that fed it.
    -- (Each INSERT's SQLROWCOUNT is available inside the transaction;
    -- the checkpoint below records the dedup count as the headline.)
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PTY_S4_DEDUP WHERE rn_pty = 1;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_TRS_PTY, C_S_TRS_PTY_RLE, STG_TRS_VALID_MEMBERS, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid parties, roles, new valid members and all exception classes. '
        || 'Count shown is valid parties loaded (rn_pty = 1); see the step-30/40 counts for exception inputs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (valid parties)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_OnGoing completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_OnGoing failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
