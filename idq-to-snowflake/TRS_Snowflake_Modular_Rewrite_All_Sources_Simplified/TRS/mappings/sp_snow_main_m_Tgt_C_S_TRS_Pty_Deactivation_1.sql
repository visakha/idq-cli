-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Deactivation_1, workflow
-- wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-39  A member is deactivated when TIERS says inactive or deleted:
--          INACTIVE_IND = 'Y' or DELETE_SW = 'Y' in STG_TRS_D_DC_INDV,
--          or INACTIVE_IND = 'Y' in STG_TRS_D_CV_DC_MCI_INDV.
--   BR-40  Deactivation capture is new-rows-only, and (in IDQ) removes
--          the member from the valid spine in the same step.  The
--          Snowflake version deliberately does NOT do the second half
--          -- see step 50 and the Parity notes.  Do not re-add it
--          without a business decision.
--   BR-50  PROCESSED_YN is the idempotency key: new log rows are written
--          'N' (unprocessed), so the later CopyList / unmerge /
--          Mark-Processed steps pick them up exactly once.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (deactv -> deactv_id
--   -> final SELECT with the already-logged guards and the per-INDV_ID
--   rank), one transaction, one log line at the end, and the IDQ
--   DD_DELETE of STG_TRS_VALID_MEMBERS as a buried comment.  If it
--   failed, nothing told you which logical stage had finished, and the
--   skipped delete was easy to miss entirely.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT, written as a single
--   INSERT from the last work table inside ONE transaction.  The skipped
--   DD_DELETE is promoted to an explicit, named, checkpointed step
--   (step 50) instead of a comment.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_DEACT1_S10_DEACTV    deactivated / deleted individuals, both sources
--   Step 20  WRK_TRS_DEACT1_S20_DEACTV_ID one row per individual: flags + earliest date
--   Step 30  WRK_TRS_DEACT1_S30_READY     valid members to log, new-rows-only,
--                                        first row per INDV_ID
--   Step 40  PUBLISH                     STG_TRS_DEACTIVED_MEMBERS (PROCESSED_YN = 'N'),
--                                        in one transaction
--   Step 50  DELETE_VALID_STAGE_NOT_PERFORMED  IDQ DD_DELETE of STG_TRS_VALID_MEMBERS:
--                                        deliberately NOT performed (checkpointed, not a comment)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_DEACT1_S10_DEACTV, WRK_TRS_DEACT1_S20_DEACTV_ID,
--   WRK_TRS_DEACT1_S30_READY.  They live in the same schema as the
--   targets (unqualified names, as in the original code), are prefixed
--   WRK_TRS_, and are registered in JOB_CONTROL_ETL at creation and
--   at drop.  They survive a session crash (TRANSIENT, not TEMP), which
--   is what makes inspection after a run possible; a pure session TEMP table would
--   vanish with the session and would be gone after a crash.  A
--   Snowflake CURSOR was NOT used: cursors process row by row, and every
--   step here is set-based by design -- the work table IS the result
--   set, held as a table instead of in memory, so it can be counted,
--   inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  In particular, the IDQ DD_DELETE of
--     STG_TRS_VALID_MEMBERS is NOT performed here (step 50).  That means
--     deactivated members STAY in the valid-member list in the Snowflake
--     version, whereas IDQ removes them -- so downstream Snowflake
--     mappings that join STG_TRS_VALID_MEMBERS will still see
--     deactivated members until some other process removes them.  This
--     is the single largest parity gap in this mapping, and it is a
--     business decision, not a bug to fix in passing: the original
--     Snowflake comment cites it as a deliberate insert-only rule.
--   * STG_TRS_DEACTIVED_MEMBERS has primary key INDV_ID, which Snowflake
--     does not enforce.  An individual can be a valid member under two
--     party keys (INDV_ID|DC_INDV and INDV_ID for MCI); IDQ writes the
--     first and the database rejects the second.  Reproduced here: one
--     row per INDV_ID (step 30 rank), and IDs already in the table are
--     skipped (di guard), as well as party keys already logged (dm guard).
--   * LOAD_DATE = run start (:l_run_ts), PROCESSED_YN = 'N' for every
--     new log row, as in the original.
--
-- SIGNATURE
--   The original procedure took no parameters, so there are no original
--   parameters to preserve.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1 (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Deactivation_1';
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
    DROP TABLE IF EXISTS WRK_TRS_DEACT1_S10_DEACTV;
    DROP TABLE IF EXISTS WRK_TRS_DEACT1_S20_DEACTV_ID;
    DROP TABLE IF EXISTS WRK_TRS_DEACT1_S30_READY;


    -- ---- Step 10: DEACTIVATED / DELETED INDIVIDUALS (BR-39) -------------
    -- Purpose: every individual flagged inactive or deleted in either
    -- source -- DC individuals where inactive_ind = 'Y' or delete_sw =
    -- 'Y', plus MCI individuals where inactive_ind = 'Y' (delete_sw is
    -- not carried for MCI, so it is NULL there).  This is the raw
    -- deactivation signal, before it is collapsed to one row per person.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_DEACT1_S10_DEACTV AS
    SELECT indv_id, inactive_ind, delete_sw, create_dt
      FROM STG_TRS_D_DC_INDV
     WHERE inactive_ind = 'Y' OR delete_sw = 'Y'
    UNION ALL
    SELECT indv_id, inactive_ind, NULL, create_dt
      FROM STG_TRS_D_CV_DC_MCI_INDV
     WHERE inactive_ind = 'Y';
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_DEACT1_S10_DEACTV;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'DEACTIVATED_INDIVIDUALS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_DEACT1_S10_DEACTV', 'CREATED',
        'Individuals flagged inactive or deleted in DC or MCI sources (BR-39). '
        || 'Read by the collapse step; the raw sources are not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 DEACTIVATED_INDIVIDUALS', :l_rows) || CHR(10);

    -- ---- Step 20: ONE ROW PER DEACTIVATED INDIVIDUAL --------------------
    -- Purpose: collapse step 10 by individual -- the strongest flags
    -- (MAX inactive_ind, MAX delete_sw) and the earliest deactivation
    -- date (MIN create_dt, as SRC_DEACTIVATION_DATE).  Reads ONLY step 10.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_DEACT1_S20_DEACTV_ID AS
    SELECT indv_id, MAX(inactive_ind) inactive_ind, MAX(delete_sw) delete_sw, MIN(create_dt) src_deactivation_date
      FROM WRK_TRS_DEACT1_S10_DEACTV
     GROUP BY indv_id;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_DEACT1_S20_DEACTV_ID;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DEACTIVATED_PER_INDIVIDUAL', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_DEACT1_S20_DEACTV_ID', 'CREATED',
        'One row per deactivated individual: strongest flags and earliest deactivation date (BR-39). '
        || 'Read by the ready step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DEACTIVATED_PER_INDIVIDUAL', :l_rows) || CHR(10);

    -- ---- Step 30: READY -- valid members to log, new-rows-only (BR-40) --
    -- Purpose: the original final SELECT, as a table.  Valid members
    -- (STG_TRS_VALID_MEMBERS) joined to step 20, keeping only rows that
    -- are NOT already logged: the party key is not in the log (dm guard,
    -- Lookup_STG_TRS_DEACTIVED_MEMBERS + Filt_New_Only, ISNULL(PTY_PK1))
    -- AND the individual is not in the log (di guard, the unenforced
    -- INDV_ID primary key).  First row per INDV_ID in this run wins
    -- (by CREATE_DATE, then PTY_PK), so a person who is a valid member
    -- under two party keys logs once.  New rows carry PROCESSED_YN = 'N'
    -- and LOAD_DATE = run start.  This table is in target column order,
    -- so step 40 is a plain INSERT ... SELECT.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_DEACT1_S30_READY AS
    SELECT vm.INDV_ID AS INDV_ID, vm.PTY_PK AS PTY_PK, vm.SRC_TBL AS SRC_TBL,
           vm.CREATE_DATE AS CREATE_DATE, d.src_deactivation_date AS SRC_DEACTIVATION_DATE,
           :l_run_ts AS LOAD_DATE, d.inactive_ind AS INACTIVE_IND, d.delete_sw AS DELETE_SW,
           'N' AS PROCESSED_YN
      FROM STG_TRS_VALID_MEMBERS vm
      JOIN WRK_TRS_DEACT1_S20_DEACTV_ID d ON d.indv_id = vm.indv_id
      LEFT JOIN (SELECT DISTINCT PTY_PK FROM STG_TRS_DEACTIVED_MEMBERS WHERE PTY_PK IS NOT NULL) dm
             ON dm.PTY_PK = vm.PTY_PK
      LEFT JOIN (SELECT DISTINCT INDV_ID FROM STG_TRS_DEACTIVED_MEMBERS) di ON di.INDV_ID = vm.INDV_ID
     WHERE dm.PTY_PK IS NULL
       AND di.INDV_ID IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY vm.INDV_ID ORDER BY vm.CREATE_DATE, vm.PTY_PK) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_DEACT1_S30_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'READY_TO_PUBLISH', 'COMPLETED', 'STG_TRS_DEACTIVED_MEMBERS', :l_rows, NULL,
        'WRK_TRS_DEACT1_S30_READY', 'CREATED',
        'Valid members to log as deactivated, new-rows-only, first row per INDV_ID, PROCESSED_YN = N (BR-40, BR-50). '
        || 'Published in step 40.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 40: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction (apart from step 50, which
    -- writes no data at all).  If the INSERT fails, it rolls back, the
    -- checkpoints for steps 10-30 (already committed) survive, the work
    -- tables survive, and the mapping must be restarted from the beginning.
    -- The INSERT below is the original INSERT, with the source changed
    -- from the deactv/deactv_id CTEs to step 30.  No TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    INSERT INTO STG_TRS_DEACTIVED_MEMBERS
           (INDV_ID, PTY_PK, SRC_TBL, CREATE_DATE, SRC_DEACTIVATION_DATE, LOAD_DATE, INACTIVE_IND, DELETE_SW,
            PROCESSED_YN)
    SELECT INDV_ID, PTY_PK, SRC_TBL, CREATE_DATE, SRC_DEACTIVATION_DATE, LOAD_DATE, INACTIVE_IND, DELETE_SW,
           PROCESSED_YN
      FROM WRK_TRS_DEACT1_S30_READY;
    l_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PUBLISH', 'COMPLETED', 'STG_TRS_DEACTIVED_MEMBERS', :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: new deactivation log rows, PROCESSED_YN = N (BR-40, BR-50). '
        || 'Count shown is rows inserted.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PUBLISH (STG_TRS_DEACTIVED_MEMBERS)', :l_rows) || CHR(10);

    -- ---- Step 50: DELETE_VALID_STAGE -- DELIBERATELY NOT PERFORMED ------------
    -- This is NOT a work-table step and it writes NO data.  It exists so
    -- that the IDQ behaviour this mapping does NOT reproduce is visible
    -- in JOB_CONTROL_ETL instead of buried in a code comment.
    --   IDQ: Delete_Valid_Stage (DD_DELETE) deletes the deactivated
    --   members from STG_TRS_VALID_MEMBERS (key PTY_PK).
    --   Snowflake: NOT performed.  This code base never deletes,
    --   truncates or drops target rows (rows are only inserted), so
    --   deactivated members stay in the valid-member list.  Downstream
    --   mappings that join STG_TRS_VALID_MEMBERS will therefore still
    --   see them -- the largest parity gap in this mapping (see Parity
    --   notes).  Re-adding the delete is a business decision, not a
    --   silent fix: it changes what every downstream mapping loads.
    -- This checkpoint is written on every run (on every run), because it records a decision, not a data step.
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'DELETE_VALID_STAGE_NOT_PERFORMED', 'COMPLETED', 'STG_TRS_VALID_MEMBERS', NULL, NULL, NULL, 'NONE',
        'IDQ DD_DELETE of STG_TRS_VALID_MEMBERS deliberately NOT performed: insert-only Snowflake rule. '
        || 'Deactivated members remain in the valid-member list (parity gap -- see header).',
        NULL,
        'Step 50 recorded: delete deliberately not performed, not forgotten.');

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Deactivation_1 completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Deactivation_1 failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
