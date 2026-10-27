-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Pln, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-26  Only rows with a plan code load as plans; the source plan code
--          must translate through the PLAN_CD crosswalk, or the row is
--          an exception -- and only the FIRST invalid row per individual
--          is logged.
--   BR-02  Every failing class goes to EXC_STG_BAD_REC_MEMB; the load
--          does not fail because of bad rows.
--   BR-10  Only MCI valid members (STG_TRS_VALID_MEMBERS, SRC_TBL = 'MCI')
--          get plans.
--   BR-01  Insert-only staging load (see Parity notes: no truncate here).
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement (two branches: valid -> plan
--   target, invalid -> exception target), one CTE chain (src -> planned
--   -> outer SELECT with the dedup rank, the invalid rank, the
--   existing-key guard and the exception lookup), one transaction, one
--   log line.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   The two branches are mutually exclusive (plan translates vs. it
--   does not), so splitting them cannot double-load a row.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_PLN_S10_SRC     managed-care rows with a plan, sane
--                                    dates, for MCI valid members (BR-26/10)
--   Step 20  WRK_TRS_PLN_S20_PLANNED plan code translated (PLAN_CD, 'MAX'),
--                                    party-role and plan keys built
--   Step 30  WRK_TRS_PLN_S30_RANKED  dedup rank, invalid rank, existing-key
--                                    guard, exception text resolved
--   Step 40  PUBLISH                 C_S_TRS_PTY_RLE_PLN + EXC_STG_BAD_REC_MEMB,
--                                    in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_PLN_S10_SRC, WRK_TRS_PLN_S20_PLANNED, WRK_TRS_PLN_S30_RANKED.
--   They live in the same schema as the targets (unqualified names, as
--   in the original code), are prefixed WRK_TRS_, and are registered in
--   JOB_CONTROL_ETL at creation.  They survive a
--   session crash (TRANSIENT, not TEMP), unlike a pure session TEMP
--   table, which would vanish with the session.  A Snowflake CURSOR was NOT used:
--   cursors process row by row, and every step here is set-based by
--   design -- the work table IS the result set, held as a table instead
--   of in memory, so it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of the targets.  IDQ truncates C_S_TRS_PTY_RLE_PLN; the
--     Snowflake version instead skips keys already present (the
--     existing-key guard in step 30) and keeps the last row per key in
--     this run.  A re-run therefore inserts nothing twice, but it also
--     does not remove rows that IDQ would have truncated away -- see
--     the User Guide, "Parity gaps".
--   * Rows whose begin date is NOT before the end date (including
--     begin = end) are dropped by the step-10 source filter, silently:
--     they are neither loaded nor exceptioned, exactly as in the
--     original.  Open-ended rows (END_DT IS NULL) do load.
--   * The plan lookup is under source system 'MAX', not 'TRS', as in the
--     original -- preserved, not "corrected".
--   * VERSION_SEQ is hard-coded to 1; PERIOD_START_DATE / PERIOD_END_DATE
--     = BEGIN_DT / END_DT of the last (latest) segment of the key.
--   * UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT and DELETED_*
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Pln';
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
    DROP TABLE IF EXISTS WRK_TRS_PLN_S10_SRC;
    DROP TABLE IF EXISTS WRK_TRS_PLN_S20_PLANNED;
    DROP TABLE IF EXISTS WRK_TRS_PLN_S30_RANKED;

    -- ---- Step 10: MANAGED-CARE SOURCE ROWS (BR-26/10) --------------------
    -- Purpose: distinct managed-care rows with a plan code, for MCI
    -- valid members only, whose period is sane (BEGIN_DT < END_DT, or
    -- open-ended).  Rows failing the date test are dropped here,
    -- silently -- they are not exceptioned (see Parity notes).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PLN_S10_SRC AS
    SELECT DISTINCT M.INDV_ID AS INDV_ID, M.BEGIN_DT, M.MC_PLAN, M.HISTORY_SEQ, M.END_DT, M.CREATE_DT
      FROM STG_TRS_D_IN_MANAGED_CARE M
      JOIN STG_TRS_VALID_MEMBERS VM ON M.INDV_ID = VM.INDV_ID AND VM.SRC_TBL = 'MCI'
     WHERE M.MC_PLAN IS NOT NULL
       AND (M.BEGIN_DT < M.END_DT OR M.END_DT IS NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PLN_S10_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'MANAGED_CARE_SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PLN_S10_SRC', 'CREATED',
        'Managed-care rows with a plan, sane dates, for MCI valid members only. '
        || 'Read by the plan-translation step (BR-26/10).',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 MANAGED_CARE_SRC', :l_rows) || CHR(10);

    -- ---- Step 20: PLAN TRANSLATION + KEYS (BR-26) ------------------------
    -- Purpose: translate the source plan code through the PLAN_CD
    -- crosswalk under source system 'MAX' (untranslated = NULL, which
    -- is what step 40's exception branch keys on), and build the
    -- party-role key (INDV_ID|Member) and the plan key
    -- (INDV_ID|Member|master code).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PLN_S20_PLANNED AS
    WITH lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT s.*,
           lk.MSTR_CODE_VALUE AS pln_mstr_cd,
           TO_VARCHAR(s.INDV_ID) || '|Member' AS pty_rle_fk,
           TO_VARCHAR(s.INDV_ID) || '|Member|' || NVL(lk.MSTR_CODE_VALUE, '') AS pkey_prty_rl_plan
      FROM WRK_TRS_PLN_S10_SRC s
      LEFT JOIN lkp_cv lk ON lk.CODE_TYPE = 'PLAN_CD' AND lk.SRC_SYS = 'MAX' AND lk.SRC_CODE_VALUE = s.MC_PLAN;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PLN_S20_PLANNED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'PLAN_TRANSLATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PLN_S20_PLANNED', 'CREATED',
        'Rows with the plan code translated (NULL when untranslatable) and both keys built. '
        || 'Read by the ranking step (BR-26).',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 PLAN_TRANSLATED', :l_rows) || CHR(10);

    -- ---- Step 30: RANK + GUARD + EXCEPTION TEXT (BR-26/02) --------------
    -- Purpose: the publish-ready rows.  rn_key = last row per plan key
    -- in sorter order (NULL high); rn_invalid = first invalid row per
    -- individual in source order (the only invalid row that gets
    -- logged); uq_pln = key not already in the plan target
    -- (VERSION_SEQ = 1); exception description/type resolved from
    -- EXC_LOOKUP_CODE_VALUE for code 'Invalid_Plan'.  The existing-key
    -- guard reads the live target here, at step time, as in the
    -- original -- a target row inserted between step 30 and publish
    -- would not be re-checked (see the User Guide on publish timing).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PLN_S30_RANKED AS
    WITH lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT p.*,
           ROW_NUMBER() OVER (PARTITION BY p.pkey_prty_rl_plan
                              ORDER BY p.BEGIN_DT DESC NULLS FIRST, p.END_DT DESC NULLS FIRST,
                                       p.pty_rle_fk DESC NULLS FIRST, p.CREATE_DT DESC NULLS FIRST) AS rn_key,
           ROW_NUMBER() OVER (PARTITION BY p.INDV_ID, p.pln_mstr_cd IS NULL
                              ORDER BY p.MC_PLAN, p.BEGIN_DT, p.END_DT) AS rn_invalid,
           xp.PKEY_SRC_OBJECT IS NULL AS uq_pln,
           1 AS version_seq,
           'TRS' AS src_sys,
           :l_run_ts AS run_ts,
           :c_mapping AS mapping_name,
           'Plan' AS attr_plan,
           'Invalid_Plan' AS exc_code,
           ex.EXCEPTION_DESC AS exc_desc,
           ex.EXCEPTION_TYPE AS exc_type,
           TO_VARCHAR(p.BEGIN_DT, 'YYYY-MM-DD') AS begin_dt_text
      FROM WRK_TRS_PLN_S20_PLANNED p
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Plan'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_PLN WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = p.pkey_prty_rl_plan;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PLN_S30_RANKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'RANKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PLN_S30_RANKED', 'CREATED',
        'Publish-ready rows: last row per plan key (rn_key), first invalid row per individual '
        || '(rn_invalid), existing-key guard (uq_pln), exception text resolved. Read by publish (BR-26/02).',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 RANKED', :l_rows) || CHR(10);

    -- ---- Step 40: PUBLISH -- one transaction, both targets ---------------
    -- This is the ONLY step that writes to final targets.  The two
    -- INSERTs below are the two branches of the original INSERT ALL,
    -- in the same order, with the same column lists, values and WHERE
    -- conditions -- only the source changed, from the outer SELECT to
    -- step 30.  If either INSERT fails, the whole publish rolls back,
    -- the step-10..30 checkpoints (already committed) survive, the
    -- work tables survive, and the mapping must be restarted from the beginning.
    BEGIN TRANSACTION;
    -- 40a. Valid plans -> C_S_TRS_PTY_RLE_PLN
    INSERT INTO C_S_TRS_PTY_RLE_PLN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, PTY_RLE_FK,
            PLN_FK, UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
            SRC_ROWID, CREATE_DATE, SRC_LAST_UPD_DT)
    SELECT pkey_prty_rl_plan, BEGIN_DT, END_DT, version_seq, run_ts, pty_rle_fk, pln_mstr_cd, NULL, NULL,
           NULL, NULL, NULL, NULL, NULL, pkey_prty_rl_plan, run_ts, CREATE_DT
      FROM WRK_TRS_PLN_S30_RANKED
     WHERE pln_mstr_cd IS NOT NULL AND rn_key = 1 AND uq_pln;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 40b. First invalid plan per individual -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, MAPPING_NAME, RUN_DATE, PERIOD_START_DATE, SRC_SYS_ID_2)
    SELECT src_sys, INDV_ID, exc_type, exc_desc, exc_code, MC_PLAN, attr_plan, mapping_name, run_ts,
           BEGIN_DT, begin_dt_text
      FROM WRK_TRS_PLN_S30_RANKED
     WHERE pln_mstr_cd IS NULL AND rn_invalid = 1;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PUBLISH', 'COMPLETED', 'C_S_TRS_PTY_RLE_PLN, EXC_STG_BAD_REC_MEMB', :l_pub_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid plans and first-invalid-plan exceptions. '
        || 'Count shown is rows inserted across both targets.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PUBLISH (plans + exceptions)', :l_pub_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Pln completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_Pln failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
