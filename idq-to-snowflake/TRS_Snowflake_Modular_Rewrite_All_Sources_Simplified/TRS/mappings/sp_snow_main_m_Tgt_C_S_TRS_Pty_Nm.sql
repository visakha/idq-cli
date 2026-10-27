-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Nm, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-21  Alias names load only for valid members, only with both a
--          first and a last name; aliases missing either are dropped
--          silently (no exception row), unlike a missing party name.
--   BR-15  Names are standardised (trailing numbers removed, then the
--          individual-member standardisation) and consolidated to one
--          row per name key.
--   BR-10  Only valid members (STG_TRS_VALID_MEMBERS spine) get names.
--   BR-01  Insert-only staging load (see Parity notes: no truncate here).
--   Name type is '002' (Alias); the staging key is
--   PKEY_PTY || '|002|' || SEQUENCE_NUM.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (src -> named -> std
--   -> dedup -> final SELECT with the existing-key guard and the
--   last-row-per-key QUALIFY), one transaction, one log line.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original final SELECT, written as a
--   single INSERT inside ONE transaction (it was the only INSERT in the
--   original, so there is nothing to split into INSERT ALL branches).
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_NM_S10_SRC    alias rows for valid members (MCI + DC)
--   Step 20  WRK_TRS_NM_S20_NAMED  both names present; trailing numbers
--                                  removed; source full name assembled
--   Step 30  WRK_TRS_NM_S30_STD    standardised names (name mapplet)
--   Step 40  WRK_TRS_NM_S40_DEDUP  distinct rows, key built (BR-21/15)
--   Step 50  PUBLISH                C_S_TRS_PTY_NM, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_NM_S10_SRC, WRK_TRS_NM_S20_NAMED, WRK_TRS_NM_S30_STD,
--   WRK_TRS_NM_S40_DEDUP.  They live in the same schema as the target
--   (unqualified names, as in the original code), are prefixed WRK_TRS_,
--   and are registered in JOB_CONTROL_ETL at creation.
--   They survive a session crash (TRANSIENT, not TEMP), which is what
--   makes inspection after a run possible; a pure session TEMP table would vanish with
--   the session.  A Snowflake CURSOR
--   was NOT used: cursors process row by row, and every step here is
--   set-based by design -- the work table IS the result set, held as a
--   table instead of in memory, so it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of the target.  IDQ truncates C_S_TRS_PTY_NM; the
--     Snowflake version instead skips keys already present (the
--     existing-key guard in the publish step) and keeps the latest
--     CREATE_DT per key in this run, whereas IDQ keeps the first that
--     arrives and the database rejects the rest.  A re-run therefore
--     inserts nothing twice, but it also does not remove rows that IDQ
--     would have truncated away -- see the User Guide, "Parity gaps".
--   * Prefix / suffix standardisation values are NULL, as in the
--     original: the name mapplet's source-system input is not linked
--     in this mapping, so its prefix/suffix lookups (keyed on the
--     source system) never match.  Preserved, not repaired -- repairing
--     it would change which names load.
--   * VERSION_SEQ is hard-coded to 1 (the consolidation rank is
--     commented out in IDQ); PERIOD_START_DATE = CREATE_DT (the
--     PERIOD_START_DATE_OUT carry-forward, which in IDQ always equals
--     the current row's CREATE_DT); PERIOD_END_DATE and
--     PERIOD_REFERENCE_TIME are NULL (unfed ports).
--   * ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR and HUB_STATE_IND
--     are NULL (unfed ports), as in the original.
--
-- SIGNATURE
--   The original parameter is unchanged and in the same order, so every
--   existing CALL still works.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm (
    P_MEMBER_NAME_TYPE_CODE VARCHAR DEFAULT '002',
    P_JOB_RUN_ID            VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Nm';
    l_run_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_pub_rows   NUMBER DEFAULT 0;
    l_summary    VARCHAR DEFAULT '';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
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
    DROP TABLE IF EXISTS WRK_TRS_NM_S10_SRC;
    DROP TABLE IF EXISTS WRK_TRS_NM_S20_NAMED;
    DROP TABLE IF EXISTS WRK_TRS_NM_S30_STD;
    DROP TABLE IF EXISTS WRK_TRS_NM_S40_DEDUP;

    -- ---- Step 10: ALIAS SOURCE ROWS (BR-21/10) ---------------------------
    -- Purpose: distinct alias rows from both sources -- MCI aliases
    -- (key = INDV_ID) and DC aliases (key = INDV_ID || '|DC_INDV') --
    -- joined to the valid-member spine on the party key, names trimmed.
    -- The commented-out absent-parent branch from the original is NOT
    -- carried forward, exactly as in the original Snowflake code.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_NM_S10_SRC AS
    SELECT DISTINCT DC_ALIAS.INDV_ID AS INDV_ID, DC_ALIAS.PKEY_PTY AS PKEY_PTY,
           RTRIM(LTRIM(DC_ALIAS.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(DC_ALIAS.MID_NAME)) AS MID_NAME,
           RTRIM(LTRIM(DC_ALIAS.LAST_NAME)) AS LAST_NAME, RTRIM(DC_ALIAS.SUFX_NAME) AS SUFX_NAME,
           RTRIM(DC_ALIAS.PREFIX_NAME) AS PREFIX_NAME, DC_ALIAS.CREATE_DT AS CREATE_DT,
           DC_ALIAS.SEQUENCE_NUM AS SEQUENCE_NUM
      FROM (SELECT INDV_ID, TO_VARCHAR(INDV_ID) AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME,
                   PREFIX_NAME, CREATE_DT, SEQUENCE_NUM
              FROM STG_TRS_D_CV_DC_MCI_ALIAS MCI_ALIAS
            UNION ALL
            SELECT INDV_ID, TO_VARCHAR(INDV_ID) || '|DC_INDV' AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME,
                   SUFX_NAME, PREFIX_NAME, CREATE_DT, SEQ_NUM
              FROM STG_TRS_D_DC_ALIAS DC_ALIAS) DC_ALIAS
      JOIN STG_TRS_VALID_MEMBERS VM ON DC_ALIAS.PKEY_PTY = VM.PTY_PK;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_NM_S10_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ALIAS_SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_NM_S10_SRC', 'CREATED',
        'Distinct alias rows for valid members only (MCI + DC aliases, spine join). '
        || 'Read by the name-presence filter step (BR-21/10).',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ALIAS_SRC', :l_rows) || CHR(10);

    -- ---- Step 20: NAMES PRESENT + TRAILING NUMBERS REMOVED (BR-21) -----
    -- Purpose: drop aliases missing a first or last name (silently --
    -- no exception row, per the IDQ filter annotation), assemble the
    -- source full name (first + middle if present + last, trimmed),
    -- and remove trailing numbers from the names
    -- (fn_snow_helper14_common).  This step is where the BR-21
    -- "both names" rule is enforced.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_NM_S20_NAMED AS
    SELECT s.*,
           TRIM(NVL(s.FIRST_NAME, '') || IFF(s.MID_NAME IS NOT NULL, ' ' || TRIM(s.MID_NAME), '')
                || ' ' || NVL(LTRIM(s.LAST_NAME), '')) AS src_full_name,
           fn_snow_helper14_common(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME, NULL) AS tn
      FROM WRK_TRS_NM_S10_SRC s
     WHERE s.FIRST_NAME IS NOT NULL AND s.LAST_NAME IS NOT NULL;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_NM_S20_NAMED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'NAMED_FILTERED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_NM_S20_NAMED', 'CREATED',
        'Aliases with both names present, source full name assembled, trailing numbers removed. '
        || 'Aliases missing a name are dropped here, silently (BR-21). Read by the standardisation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 NAMED', :l_rows) || CHR(10);

    -- ---- Step 30: STANDARDISED NAMES (BR-15) -----------------------------
    -- Purpose: run the individual-member name standardisation
    -- (fn_snow_helper15_common) over the trailing-number-cleaned names,
    -- with the source prefix/suffix and full name.  The junk-name
    -- flags come from fn_snow_helper43_common.  Prefix/suffix lookup
    -- values are passed as NULL, exactly as in the original, so the
    -- standardised prefix/suffix are NULL (see Parity notes).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_NM_S30_STD AS
    WITH lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT n.*,
           fn_snow_helper15_common(n.tn:first_name::VARCHAR, n.tn:middle_name::VARCHAR, n.tn:last_name::VARCHAR,
                                   n.src_full_name, n.PREFIX_NAME, n.SUFX_NAME, NULL, NULL,
                                   jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
      FROM WRK_TRS_NM_S20_NAMED n
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(n.tn:first_name::VARCHAR)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(n.tn:last_name::VARCHAR)) AND jl.IS_LAST_JUNK;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_NM_S30_STD;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'STANDARDISED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_NM_S30_STD', 'CREATED',
        'Standardised names (name mapplet output in nm). Read by the de-duplication step (BR-15).',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 STD', :l_rows) || CHR(10);

    -- ---- Step 40: DE-DUPLICATE + KEY (BR-15) ------------------------------
    -- Purpose: distinct standardised rows with the staging key
    -- PKEY_PTY || '|' || name-type code || '|' || SEQUENCE_NUM.
    -- Gender is an unfed port (NULL) and is left out, as in the
    -- original.  This is the exact input to the publish step; the
    -- existing-key guard and the last-row-per-key rank stay in the
    -- publish SELECT, as in the original, because they read the live
    -- target at publish time.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_NM_S40_DEDUP AS
    SELECT DISTINCT s.PKEY_PTY, s.CREATE_DT, s.nm:sfx_name::VARCHAR AS sfx_nm,
           s.nm:first_name::VARCHAR AS frst_nm, s.nm:prfx_name::VARCHAR AS prfx_nm,
           s.nm:last_name::VARCHAR AS lst_nm, s.nm:middle_name::VARCHAR AS mdl_nm,
           s.nm:full_name::VARCHAR AS full_nm, s.src_full_name, s.SEQUENCE_NUM,
           NVL(s.PKEY_PTY, '') || '|' || :P_MEMBER_NAME_TYPE_CODE || '|' || NVL(TO_VARCHAR(s.SEQUENCE_NUM), '')
                                                                                        AS pkey_src_object
      FROM WRK_TRS_NM_S30_STD s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_NM_S40_DEDUP;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'DEDUP_KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_NM_S40_DEDUP', 'CREATED',
        'Distinct standardised rows with the PKEY_PTY|type|sequence key. '
        || 'Read by the publish step (BR-15/21).',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 DEDUP', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction -----------------------------
    -- This is the ONLY step that writes to a final target.  The INSERT
    -- below is the original final SELECT verbatim, with its FROM
    -- pointed at step 40: keys already in C_S_TRS_PTY_NM
    -- (VERSION_SEQ = 1) are skipped, and only the latest CREATE_DT row
    -- per key (then full name) loads.
    BEGIN TRANSACTION;
    INSERT INTO C_S_TRS_PTY_NM
           (PTY_FK, SFX_NM, FRST_NM, PFX_NM, LST_NM, MDL_NM, FULL_NM, VERSION_SEQ, LAST_UPDATE_DATE, NM_TP, SRC_ROWID,
            ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_END_DATE, PERIOD_REFERENCE_TIME, UPDATED_BY,
            CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_FULL_NM, SRC_LAST_UPD_DT, PKEY_SRC_OBJECT, PERIOD_START_DATE)
    SELECT d.PKEY_PTY, d.sfx_nm, d.frst_nm, d.prfx_nm, d.lst_nm, d.mdl_nm, d.full_nm,
           1, :l_run_ts, :P_MEMBER_NAME_TYPE_CODE, d.pkey_src_object,
           NULL, NULL, NULL, NULL, NULL, NULL, NULL, d.CREATE_DT, NULL,
           NULL, d.src_full_name, d.CREATE_DT, d.pkey_src_object,
           d.CREATE_DT
      FROM WRK_TRS_NM_S40_DEDUP d
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_NM WHERE VERSION_SEQ = 1) xn
             ON xn.PKEY_SRC_OBJECT = d.pkey_src_object
     WHERE xn.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object ORDER BY d.CREATE_DT DESC NULLS LAST, d.full_nm) = 1;
    l_pub_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED', 'C_S_TRS_PTY_NM', :l_pub_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: alias names for valid members. '
        || 'Count shown is rows inserted into C_S_TRS_PTY_NM.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (C_S_TRS_PTY_NM)', :l_pub_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Nm completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_TRS_Pty_Nm failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
