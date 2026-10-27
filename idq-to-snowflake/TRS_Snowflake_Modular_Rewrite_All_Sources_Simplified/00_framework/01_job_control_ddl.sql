-- ============================================================================
-- 01_job_control_ddl.sql  (multi-source)
--
-- The job-control table for the Snowflake drop-in replacement of the
-- multi-source IDQ estate (TRS, ECI, WIC, TTF, FSS, CRE).  One shared
-- table in MDM_ETL_COMMON.COMMON, distinguished by SOURCE; each source
-- installs its own mappings into MDM_ETL_<SRC>.<SRC>_ETL_WRK.  One table, three states, no extra licences:
-- only tables, views and stored procedures are used (no Snowflake
-- Dataflow / Dynamic Tables / Streams / Tasks are required by this design).
--
-- WHY THIS TABLE EXISTS
--   The original Snowflake procedures were one giant INSERT ALL statement
--   inside one transaction.  If that statement failed, or the session died,
--   there was nothing to look at except a rolled-back transaction: no record
--   of which logical step had finished, how many rows it produced, or which
--   intermediate result existed.  These rewritten procedures therefore
--   write a checkpoint row to JOB_CONTROL_ETL after EVERY step, and
--   those checkpoint writes are deliberately NOT inside the mapping's
--   publish transaction, so they survive a rollback and a crash.
--
-- THE THREE STATES (exactly as specified)
--   STARTING     -- the job / mapping has begun.  One row per run.
--   WORKING      -- a step has started / finished.
--                  This is the "transition state": it tells a reviewer
--                  exactly how far the data flow got.
--   TERMINATING  -- the job / mapping has ended.  Two flavours:
--                  COMPLETED = published; work tables are left in place
--                  (they are cleaned up only at the start of the NEXT run
--                  of that mapping), FAILED = stopped, work tables KEPT.
--                  A TERMINATING row is the "final terminating state":
--                  a run with no TERMINATING row is, by definition, a run
--                  that was interrupted.
--
-- ONE ROW PER EVENT, NEVER UPDATED
--   Checkpoints are append-only.  There is no resume: a restart is a
--   new run with a new JOB_RUN_ID, and the failed run's history stays
--   intact for comparison.  The "current state" of a run is simply
--   its latest row (see VW_ETL_JOB_CURRENT below).  Never TRUNCATE or
--   DELETE from this table as part of a job run; prune it only by an
--   explicit, dated housekeeping decision (see the User Guide).
--
-- NAMING NOTE
--   Snowflake folds unquoted identifiers to upper case, so the table the
--   user asked for as Job_Control_ETL_TRS is created here as
--   JOB_CONTROL_ETL.  Quoted "Job_Control_ETL_TRS" would be a different,
--   case-sensitive object and is deliberately NOT used, so that every
--   procedure, view and ad-hoc query can refer to it without quotes.
-- ============================================================================

CREATE TABLE IF NOT EXISTS JOB_CONTROL_ETL (
    -- Identity of the run.  One JOB_RUN_ID = one attempt at one mapping
    -- (a workflow run re-uses the same JOB_RUN_ID for every mapping it
    -- calls, so a workflow's whole history can be read with one filter).
    EVENT_ID            NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    JOB_RUN_ID          VARCHAR(100)  NOT NULL,
    SOURCE              VARCHAR(10)   NOT NULL,   -- TRS | ECI | WIC | TTF | FSS | CRE
    WORKFLOW_NAME       VARCHAR(200)  NOT NULL,
    MAPPING_NAME        VARCHAR(200)  NOT NULL,

    -- The three states.
    STATE               VARCHAR(20)   NOT NULL,   -- STARTING | WORKING | TERMINATING
    STEP_NO             NUMBER(4)     NOT NULL,   -- 0 = job begin, 999 = job end, 1..n = steps
    STEP_NAME           VARCHAR(200)  NOT NULL,
    STEP_STATUS         VARCHAR(30)   NOT NULL,   -- STARTED | COMPLETED | FAILED

    -- What the step read / wrote.  ROW_COUNT is the step's own output
    -- (rows in the work table it created, or rows inserted by a publish
    -- step).  SOURCE_ROW_COUNT is filled where the step's input count is
    -- a useful second number (e.g. publish: rows read from the work table).
    TARGET_TABLE        VARCHAR(200),
    ROW_COUNT           NUMBER(38),
    SOURCE_ROW_COUNT    NUMBER(38),

    -- The work-table boundary, in the checkpoint itself.  This is what
    -- makes "which temp/work tables exist, and may I delete them?" a
    -- query instead of a guess (see VW_ETL_OPEN_WORK_TABLES).
    WORK_TABLE_NAME     VARCHAR(200),             -- e.g. WRK_TRS_PTY_S2_DQ, or NULL if the step uses none
    WORK_TABLE_ACTION   VARCHAR(30)   NOT NULL DEFAULT 'NONE',
                                                  -- CREATED | DROPPED (retained value; step 5 no longer writes one) | KEPT | NONE
    WORK_TABLE_PURPOSE  VARCHAR(1000),            -- why this table was created, in business words
    DROP_REASON         VARCHAR(1000),            -- why it is no longer needed (only on DROPPED rows)

    -- Human-readable trail.
    MESSAGE             VARCHAR(4000),
    ERROR_MESSAGE       VARCHAR(4000),

    EVENT_TS            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY          VARCHAR(100)  DEFAULT CURRENT_USER()
);

COMMENT ON TABLE JOB_CONTROL_ETL IS
    'Append-only checkpoint log for the multi-source Snowflake ETL (SOURCE = TRS | ECI | WIC | TTF | FSS | CRE). STATE is STARTING, WORKING or TERMINATING. '
    || 'The latest row per JOB_RUN_ID is the run current state; a run with no TERMINATING row was interrupted. '
    || 'Never truncate this table as part of a job run.';

-- ============================================================================
-- Views: the three questions a reviewer / operator asks most often.
-- ============================================================================

-- Q1: "Where is each run right now?"  One row per JOB_RUN_ID.
CREATE OR REPLACE VIEW VW_ETL_JOB_CURRENT AS
SELECT SOURCE, JOB_RUN_ID, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
       STEP_STATUS, TARGET_TABLE, ROW_COUNT, WORK_TABLE_NAME,
       WORK_TABLE_ACTION, MESSAGE, ERROR_MESSAGE, EVENT_TS
  FROM JOB_CONTROL_ETL
 QUALIFY ROW_NUMBER() OVER (PARTITION BY SOURCE, JOB_RUN_ID, MAPPING_NAME
                            ORDER BY EVENT_ID DESC) = 1;

-- Q2: "What did each step of a run do?"  Latest status per step.
CREATE OR REPLACE VIEW VW_ETL_JOB_STEPS AS
SELECT SOURCE, JOB_RUN_ID, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
       STEP_STATUS, TARGET_TABLE, ROW_COUNT, SOURCE_ROW_COUNT,
       WORK_TABLE_NAME, WORK_TABLE_ACTION, WORK_TABLE_PURPOSE, DROP_REASON,
       MESSAGE, ERROR_MESSAGE, EVENT_TS
  FROM JOB_CONTROL_ETL
 QUALIFY ROW_NUMBER() OVER (PARTITION BY SOURCE, JOB_RUN_ID, MAPPING_NAME, STEP_NO
                            ORDER BY EVENT_ID DESC) = 1;

-- Q3: "Which work tables are still lying around, and may I drop them?"
-- A work table is OPEN when its latest action for that run is CREATED
-- or KEPT -- i.e. it has not been dropped at the start of a later run.
-- By design, even COMPLETED runs have open work tables: they stay in
-- the database until the next run of that mapping cleans them up.
CREATE OR REPLACE VIEW VW_ETL_OPEN_WORK_TABLES AS
SELECT SOURCE, JOB_RUN_ID, WORKFLOW_NAME, MAPPING_NAME, WORK_TABLE_NAME,
       WORK_TABLE_ACTION, WORK_TABLE_PURPOSE, EVENT_TS AS LAST_ACTION_TS
  FROM JOB_CONTROL_ETL
 WHERE WORK_TABLE_NAME IS NOT NULL
 QUALIFY ROW_NUMBER() OVER (PARTITION BY SOURCE, JOB_RUN_ID, WORK_TABLE_NAME
                            ORDER BY EVENT_ID DESC) = 1
   AND WORK_TABLE_ACTION IN ('CREATED', 'KEPT');

-- Q4: "Which runs need attention?"  Failed, or interrupted (no TERMINATING row).
CREATE OR REPLACE VIEW VW_ETL_RUNS_NEEDING_ATTENTION AS
SELECT c.SOURCE, c.JOB_RUN_ID, c.WORKFLOW_NAME, c.MAPPING_NAME, c.STATE, c.STEP_NO,
       c.STEP_NAME, c.STEP_STATUS, c.ERROR_MESSAGE, c.EVENT_TS,
       CASE WHEN c.STEP_STATUS = 'FAILED' THEN 'FAILED - work tables left in place; restart with a new run'
            ELSE 'INTERRUPTED - no TERMINATING row, treat as failed and restart with a new run'
       END AS RECOMMENDED_ACTION
  FROM VW_ETL_JOB_CURRENT c
 WHERE c.STEP_STATUS = 'FAILED'
    OR c.STATE <> 'TERMINATING';

-- Q5: "Show me a whole run, in order, as a story."  (Use this in reviews.)
CREATE OR REPLACE VIEW VW_ETL_JOB_STORY AS
SELECT SOURCE, JOB_RUN_ID, WORKFLOW_NAME, MAPPING_NAME, EVENT_ID, EVENT_TS,
       STATE, STEP_NO, STEP_NAME, STEP_STATUS, TARGET_TABLE, ROW_COUNT,
       WORK_TABLE_NAME, WORK_TABLE_ACTION, WORK_TABLE_PURPOSE, DROP_REASON,
       MESSAGE
  FROM JOB_CONTROL_ETL;
