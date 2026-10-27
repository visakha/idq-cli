-- ============================================================================
-- 02_job_control_procs.sql  (multi-source)
--
-- The only procedures that write to JOB_CONTROL_ETL (shared, MDM_ETL_COMMON.COMMON).
-- Every call takes SOURCE first, so one control table serves all six sources.  Mapping
-- procedures never INSERT into the control table directly: they CALL
-- these, so the checkpoint format, the three states and the work-table
-- registry stay identical across every mapping, and a future change to
-- the log format is a change in one file, not fifteen.
--
-- TRANSACTION RULE (read this before changing anything):
--   These procedures contain a single INSERT and no transaction control.
--   Called from a mapping procedure that is NOT inside an explicit
--   transaction, that INSERT autocommits immediately -- which is exactly
--   what self-healing needs: the checkpoint survives a later rollback.
--   Called from inside a publish transaction, it would roll back with
--   that transaction -- which is why mapping procedures are written as:
--     steps (autocommitted) -> checkpoints -> ONE publish transaction
--     -> COMMIT -> terminating checkpoint.  Never call a checkpoint
--   between BEGIN TRANSACTION and COMMIT inside a mapping.
--
-- RETURN VALUES
--   sp_etl_job_begin returns the JOB_RUN_ID to use for the whole run.
--   The other procedures return a short 'OK' string; callers ignore it
--   except in ad-hoc use.  (Snowflake SQL procedures are called as
--   statements, so mapping code CALLs them and does not assign their
--   result -- the run id is generated locally where it is needed, see
--   the template in 02_mappings.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- sp_etl_job_begin
--   Starts a run.  If P_JOB_RUN_ID is NULL, a new id is generated and
--   returned; if one is supplied (a workflow runner passing its run id,
--   or an operator running one mapping under a specific run id), that id
--   is used.  Writes the STARTING row (STEP_NO 0).  Every run is a new
--   run: there is no resume mode, and a restart is simply a new run id.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_job_begin (
    P_SOURCE        VARCHAR,
    P_WORKFLOW_NAME VARCHAR,
    P_MAPPING_NAME  VARCHAR,
    P_JOB_RUN_ID    VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    l_job_run_id VARCHAR DEFAULT :P_JOB_RUN_ID;
BEGIN
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := :P_SOURCE || '_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
                        || '_' || UUID_STRING();
    END IF;

    INSERT INTO JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, WORK_TABLE_ACTION, MESSAGE)
    VALUES (:l_job_run_id, :P_SOURCE, :P_WORKFLOW_NAME, :P_MAPPING_NAME, 'STARTING', 0,
            'JOB_BEGIN', 'STARTED', 'NONE',
            'Job started. Work tables for this run '
            || 'will be registered here step by step; see VW_ETL_JOB_STORY.');

    RETURN l_job_run_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- sp_etl_checkpoint
--   The one checkpoint writer.  Every argument is optional except the
--   identity (run / workflow / mapping) and the step description, so a
--   mapping step can record exactly what it did and nothing it did not:
--     * a step that creates a work table: WORK_TABLE_ACTION = 'CREATED'
--       and WORK_TABLE_PURPOSE = why, in business words.
--     * a step that drops a work table: WORK_TABLE_ACTION = 'DROPPED'
--       and DROP_REASON = why it is no longer needed. (Retained value:
--       step 5 cleanup no longer writes a checkpoint for its drops.)
--     * a step that leaves a work table behind: 'KEPT' (work tables are
--       never dropped at the end of a run, and the exception handler
--       does not drop anything either -- the next run cleans them up).
--   STATE must be 'STARTING', 'WORKING' or 'TERMINATING'.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_checkpoint (
    P_SOURCE            VARCHAR,
    P_JOB_RUN_ID        VARCHAR,
    P_WORKFLOW_NAME     VARCHAR,
    P_MAPPING_NAME      VARCHAR,
    P_STATE             VARCHAR,                    -- STARTING | WORKING | TERMINATING
    P_STEP_NO           NUMBER,
    P_STEP_NAME         VARCHAR,
    P_STEP_STATUS       VARCHAR,                    -- STARTED | COMPLETED | FAILED
    P_TARGET_TABLE      VARCHAR DEFAULT NULL,
    P_ROW_COUNT         NUMBER  DEFAULT NULL,
    P_SOURCE_ROW_COUNT  NUMBER  DEFAULT NULL,
    P_WORK_TABLE_NAME   VARCHAR DEFAULT NULL,
    P_WORK_TABLE_ACTION VARCHAR DEFAULT 'NONE',     -- CREATED | DROPPED | KEPT | NONE
    P_WORK_TABLE_PURPOSE VARCHAR DEFAULT NULL,
    P_DROP_REASON       VARCHAR DEFAULT NULL,
    P_MESSAGE           VARCHAR DEFAULT NULL,
    P_ERROR_MESSAGE     VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    INSERT INTO JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, TARGET_TABLE, ROW_COUNT, SOURCE_ROW_COUNT,
            WORK_TABLE_NAME, WORK_TABLE_ACTION, WORK_TABLE_PURPOSE, DROP_REASON,
            MESSAGE, ERROR_MESSAGE)
    VALUES (:P_JOB_RUN_ID, :P_SOURCE, :P_WORKFLOW_NAME, :P_MAPPING_NAME, :P_STATE,
            :P_STEP_NO, :P_STEP_NAME, :P_STEP_STATUS, :P_TARGET_TABLE,
            :P_ROW_COUNT, :P_SOURCE_ROW_COUNT, :P_WORK_TABLE_NAME,
            :P_WORK_TABLE_ACTION, :P_WORK_TABLE_PURPOSE, :P_DROP_REASON,
            :P_MESSAGE, :P_ERROR_MESSAGE);

    RETURN 'CHECKPOINT_OK';
END;
$$;

-- ----------------------------------------------------------------------------
-- sp_etl_job_finish  (TERMINATING / COMPLETED)
--   Call AFTER the publish transaction has committed.  Work tables are
--   NOT dropped at the end of a run -- they stay in the database until
--   the next run of the mapping cleans them up at its start (step 5).
--   This row is the run's final terminating state: a reviewer can tell
--   a completed run from an interrupted one by the presence of this row.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_job_finish (
    P_SOURCE        VARCHAR,
    P_JOB_RUN_ID    VARCHAR,
    P_WORKFLOW_NAME VARCHAR,
    P_MAPPING_NAME  VARCHAR,
    P_MESSAGE       VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    INSERT INTO JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, WORK_TABLE_ACTION, MESSAGE)
    VALUES (:P_JOB_RUN_ID, :P_SOURCE, :P_WORKFLOW_NAME, :P_MAPPING_NAME, 'TERMINATING',
            999, 'JOB_END', 'COMPLETED', 'NONE',
            COALESCE(:P_MESSAGE,
                     'Job completed. Final targets published; work tables left in place '
                     || 'until the next run of this mapping cleans them up at its start. '
                     || 'See VW_ETL_JOB_STORY for the step-by-step counts.'));

    RETURN 'JOB_COMPLETED';
END;
$$;

-- ----------------------------------------------------------------------------
-- sp_etl_job_fail  (TERMINATING / FAILED)
--   Call from an exception handler AFTER any rollback, so that this row
--   itself is not rolled back.  It deliberately does NOT drop work
--   tables: on failure the work tables are KEPT (that is the point --
--   inspect them, fix the cause, then restart the mapping with a new
--   run; its step-5 cleanup will drop them).  The handler in each mapping
--   also writes a KEPT row before calling this, so VW_ETL_OPEN_WORK_TABLES
--   lists exactly what survived.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_job_fail (
    P_SOURCE        VARCHAR,
    P_JOB_RUN_ID    VARCHAR,
    P_WORKFLOW_NAME VARCHAR,
    P_MAPPING_NAME  VARCHAR,
    P_ERROR_MESSAGE VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    INSERT INTO JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, WORK_TABLE_ACTION, ERROR_MESSAGE, MESSAGE)
    VALUES (:P_JOB_RUN_ID, :P_SOURCE, :P_WORKFLOW_NAME, :P_MAPPING_NAME, 'TERMINATING',
            999, 'JOB_END', 'FAILED', 'NONE', :P_ERROR_MESSAGE,
            'Job failed. Work tables KEPT for inspection; nothing '
            || 'was dropped. Query VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID, '
            || 'fix the cause, then restart the mapping with a new run.');

    RETURN 'JOB_FAILED';
END;
$$;

-- ----------------------------------------------------------------------------
