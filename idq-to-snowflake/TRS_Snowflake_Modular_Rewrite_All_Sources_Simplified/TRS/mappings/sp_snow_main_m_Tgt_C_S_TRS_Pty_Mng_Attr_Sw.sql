-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-34  Switch attributes are unpivoted into attribute rows; null/blank
--          values are dropped, never loaded and never exceptioned.
--   BR-10  Only valid members (STG_TRS_VALID_MEMBERS spine) get attributes.
--   BR-01  Insert-only staging load (see Parity notes: no truncate here).
--   Runs BEFORE m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, which appends
--   its own attribute type to the same table (BR-35).  The two mappings
--   must run in that order, never in parallel.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (daily_indv -> src ->
--   normalized -> attrs -> final SELECT with the existing-key guard and
--   the last-row-per-key QUALIFY), one transaction, one log line.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original final SELECT, written as a
--   single INSERT inside ONE transaction (it was the only INSERT in the
--   original, so there is nothing to split into INSERT ALL branches).
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_MNGSW_S10_DAILY  latest DC/MCI row per individual (BR-34)
--   Step 20  WRK_TRS_MNGSW_S20_SRC    valid members only, latest row kept (BR-10)
--   Step 30  WRK_TRS_MNGSW_S30_NORM   one row per switch attribute (5 branches)
--   Step 40  WRK_TRS_MNGSW_S40_ATTRS  distinct keys, null/blank values dropped
--   Step 50  PUBLISH                  C_S_TRS_PTY_MNG_ATTR, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_MNGSW_S10_DAILY, WRK_TRS_MNGSW_S20_SRC, WRK_TRS_MNGSW_S30_NORM,
--   WRK_TRS_MNGSW_S40_ATTRS.  They live in the same schema as the target
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
--     DELETE of the target.  IDQ truncates C_S_TRS_PTY_MNG_ATTR; the
--     Snowflake version instead skips keys already present (the
--     existing-key guard in the publish step) and keeps the last row
--     per key in this run.  A re-run therefore inserts nothing twice,
--     but it also does not remove rows that IDQ would have truncated
--     away -- see the User Guide, "Parity gaps".
--   * VERSION_SEQ is hard-coded to 1 (the running version counter is
--     commented out in IDQ); PERIOD_START_DATE = EFF_BEGIN_DT;
--     PERIOD_END_DATE, PERIOD_REFERENCE_TIME and TIMELINE_ACTION are
--     NULL (unfed ports).
--   * ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR and HUB_STATE_IND
--     are NULL (unfed ports), as in the original.
--
-- SIGNATURE
--   The original procedure took no parameters, so there is nothing to
--   preserve in order.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw (
    P_JOB_RUN_ID  VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Sw';
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
    DROP TABLE IF EXISTS WRK_TRS_MNGSW_S10_DAILY;
    DROP TABLE IF EXISTS WRK_TRS_MNGSW_S20_SRC;
    DROP TABLE IF EXISTS WRK_TRS_MNGSW_S30_NORM;
    DROP TABLE IF EXISTS WRK_TRS_MNGSW_S40_ATTRS;

    -- ---- Step 10: DAILY INDIVIDUALS (BR-34) ------------------------------
    -- Purpose: the latest DC_INDV and MCI row per individual, with the
    -- per-individual rank that step 20 uses to keep only the latest.
    -- DC rows carry the clearance/SSA switches; MCI rows carry the
    -- TW/LTC conversion indicators.  Nothing is filtered yet.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGSW_S10_DAILY AS
    SELECT dc.indv_id AS INDV_ID, dc.FILE_CLEARANCE_SW, dc.SSA_VALIDATION_SW, dc.CREATE_DT AS EFF_BEGIN_DT,
           NULL AS TW_CONVERT_IND, NULL AS LTC_CONVERT_IND, TO_VARCHAR(dc.INDV_ID) || '|DC_INDV' AS PTY_PK,
           dc.create_dt AS CREATE_DT, 'DC_INDV' AS SRC_TBL,
           ROW_NUMBER() OVER (PARTITION BY dc.INDV_ID ORDER BY dc.CREATE_DT DESC) AS KEY_RN
      FROM STG_TRS_D_DC_INDV dc
    UNION
    SELECT cv.indv_id, NULL, NULL, cv.create_dt, cv.TW_CONVERT_IND, cv.LTC_CONVERT_IND, TO_VARCHAR(cv.INDV_ID),
           cv.create_dt, 'MCI', ROW_NUMBER() OVER (PARTITION BY cv.INDV_ID ORDER BY cv.CREATE_DT DESC)
      FROM STG_TRS_D_CV_DC_MCI_INDV cv;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGSW_S10_DAILY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'DAILY_INDV', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGSW_S10_DAILY', 'CREATED',
        'Latest DC/MCI row per individual, ranked (KEY_RN). Read by the valid-member step (BR-34).',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 DAILY_INDV', :l_rows) || CHR(10);

    -- ---- Step 20: VALID MEMBERS ONLY (BR-10) -----------------------------
    -- Purpose: keep only the latest row per individual (KEY_RN = 1) and
    -- only individuals on the valid-member spine, matched on individual
    -- AND source table.  Every later step reads this table, never the
    -- raw sources again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGSW_S20_SRC AS
    SELECT dly.INDV_ID, dly.FILE_CLEARANCE_SW, dly.SSA_VALIDATION_SW, dly.EFF_BEGIN_DT, dly.TW_CONVERT_IND,
           dly.LTC_CONVERT_IND, dly.PTY_PK, dly.CREATE_DT, dly.SRC_TBL
      FROM WRK_TRS_MNGSW_S10_DAILY dly
      JOIN STG_TRS_VALID_MEMBERS IM ON dly.INDV_ID = IM.INDV_ID AND dly.SRC_TBL = IM.SRC_TBL
     WHERE dly.KEY_RN = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGSW_S20_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'VALID_SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGSW_S20_SRC', 'CREATED',
        'Latest row per valid member only (KEY_RN = 1, joined to STG_TRS_VALID_MEMBERS). '
        || 'Read by the unpivot step; never re-read the raw sources after this point.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 VALID_SRC', :l_rows) || CHR(10);

    -- ---- Step 30: UNPIVOT -- one row per switch (BR-34) ------------------
    -- Purpose: turn the five switch columns into five attribute rows
    -- per person: File_Clearance_SW, SSA_Validation_SW, TW_Convert_Ind,
    -- LTC_Convert_Ind and Source_Table.  Blank/null values are still
    -- present here; step 40 drops them.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGSW_S30_NORM AS
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT AS SRC_LAST_UPD_DT, 'File_Clearance_SW' AS ATTR_TYPE,
           TO_VARCHAR(s.FILE_CLEARANCE_SW) AS ATTR_VALUE FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'SSA_Validation_SW', TO_VARCHAR(s.SSA_VALIDATION_SW) FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'TW_Convert_Ind', TO_VARCHAR(s.TW_CONVERT_IND) FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'LTC_Convert_Ind', TO_VARCHAR(s.LTC_CONVERT_IND) FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'Source_Table', TO_VARCHAR(s.SRC_TBL) FROM WRK_TRS_MNGSW_S20_SRC s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGSW_S30_NORM;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'UNPIVOT_SWITCHES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGSW_S30_NORM', 'CREATED',
        'One row per switch attribute (five branches: clearance, SSA, TW, LTC, source table). '
        || 'Read by the null/blank filter step (BR-34).',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 UNPIVOT', :l_rows) || CHR(10);

    -- ---- Step 40: FILTER + KEY -- distinct, present values only (BR-34) --
    -- Purpose: drop null/blank switch values (IDQ blank test via
    -- fn_snow_helper03_common), build the staging key
    -- PTY_PK || '|' || attribute type, and de-duplicate.  This is the
    -- exact input to the publish step; the existing-key guard and the
    -- last-row-per-key rank stay in the publish SELECT, as in the
    -- original, because they read the live target at publish time.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGSW_S40_ATTRS AS
    SELECT DISTINCT NVL(a.PTY_PK, '') || '|' || a.ATTR_TYPE AS pkey_src_object, a.EFF_BEGIN_DT, a.PTY_PK,
           a.ATTR_TYPE, a.ATTR_VALUE, a.SRC_LAST_UPD_DT
      FROM WRK_TRS_MNGSW_S30_NORM a
     WHERE NOT fn_snow_helper03_common(a.ATTR_VALUE);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGSW_S40_ATTRS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'FILTERED_ATTRS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGSW_S40_ATTRS', 'CREATED',
        'Distinct attribute rows with a present, non-blank value and the PTY_PK|type key. '
        || 'Read by the publish step (BR-34).',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ATTRS', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction -----------------------------
    -- This is the ONLY step that writes to a final target.  The INSERT
    -- below is the original final SELECT verbatim, with its FROM
    -- pointed at step 40: keys already in C_S_TRS_PTY_MNG_ATTR
    -- (VERSION_SEQ = 1) are skipped, and only the last row per key
    -- (latest EFF_BEGIN_DT) loads.
    BEGIN TRANSACTION;
    INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            MNG_ATTR_TP, MNG_ATTR_VAL, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE,
            SRC_ROWID, CREATOR, LAST_UPDATE_DATE, SRC_LAST_UPD_DT, PTY_FK, HUB_STATE_IND)
    SELECT t.pkey_src_object, NULL, NULL, NULL, NULL, t.EFF_BEGIN_DT, NULL,
           t.ATTR_TYPE, t.ATTR_VALUE, 1, NULL, NULL, NULL, :l_run_ts, t.pkey_src_object, NULL, :l_run_ts, t.SRC_LAST_UPD_DT,
           t.PTY_PK, NULL
      FROM WRK_TRS_MNGSW_S40_ATTRS t
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_MNG_ATTR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = t.pkey_src_object
     WHERE xa.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.pkey_src_object ORDER BY t.EFF_BEGIN_DT DESC NULLS LAST) = 1;
    l_pub_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED', 'C_S_TRS_PTY_MNG_ATTR', :l_pub_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: switch attributes for valid members. '
        || 'Count shown is rows inserted into C_S_TRS_PTY_MNG_ATTR.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (C_S_TRS_PTY_MNG_ATTR)', :l_pub_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Mng_Attr_Sw completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Mng_Attr_Sw failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
