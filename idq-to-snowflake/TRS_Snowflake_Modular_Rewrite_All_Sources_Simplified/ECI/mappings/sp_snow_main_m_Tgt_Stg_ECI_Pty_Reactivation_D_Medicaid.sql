-- ============================================================================
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid
--   --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Meant to move the latest history row of each Medicaid record of a
--   reactivated child into the delta table. See the parity note below:
--   with the default parameter value it writes no rows, exactly as the
--   original does.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement (history join to the latest-load
--   subquery, delta-table lookup, keep-new filter, one-row-per-id
--   rank), one transaction, one log line.
--   This rewrite splits that single statement at its natural boundary
--   into two staged steps plus publish. No business expression was
--   changed. FLAG: this original has no CTE chain, so the split below
--   is the closest sensible split (latest rows plus lookup, then
--   keep-new filter plus rank, then publish), not a CTE-boundary split.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_RFM_S10_LATEST   latest history row per Medicaid
--                                     record of reactivated children,
--                                     plus the delta-table lookup key
--   Step 20  WRK_ECI_RFM_S20_KEEPNEW  rows passing the keep-new filter,
--                                     one row per Medicaid id
--   Step 30  PUBLISH                STG_ECI_D_MEDICAID, in one
--                                     transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_RFM_S10_LATEST, WRK_ECI_RFM_S20_KEEPNEW. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * PRESERVED DEFECT: the keep-new filter tests the SOURCE port
--     ID_MEDICAID, not the lookup result, when P_TEST_LOOKUP_RESULT
--     is 'N' (the default). ID_MEDICAID is the history key and never
--     NULL, so with the default the mapping writes no rows, exactly as
--     IDQ does. Passing 'Y' tests the lookup result instead and keeps
--     records not yet in STG_ECI_D_MEDICAID (the intended behaviour,
--     as the family address / phone reactivation mappings do).
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. STG_ECI_D_MEDICAID has primary key
--     ID_MEDICAID, which Snowflake does not enforce: with 'Y', one row
--     per ID_MEDICAID is written and ids already in the table are
--     skipped (the step-20 rank plus the lookup filter).
--   * No validation rule runs here; preserved.
--
-- SIGNATURE
--   The original parameter is unchanged and in the same order, so
--   every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (
    P_TEST_LOOKUP_RESULT VARCHAR DEFAULT 'N',
    P_JOB_RUN_ID         VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'ECI';
    c_workflow   VARCHAR DEFAULT 'wf_ECI_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid';
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_summary    VARCHAR DEFAULT '';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(:P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin('ECI', :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    DROP TABLE IF EXISTS WRK_ECI_RFM_S10_LATEST;
    DROP TABLE IF EXISTS WRK_ECI_RFM_S20_KEEPNEW;

    -- ---- Step 10: LATEST HISTORY ROWS + LOOKUP ----------------------------
    -- Purpose: the latest-load history row of each Medicaid record of
    -- a reactivated child (via the case table), plus the delta-table
    -- lookup key (LKP_ID_MEDICAID, NULL when the id is not yet in the
    -- delta table). This is the history-to-latest join plus the
    -- delta-table lookup of the original INSERT.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_RFM_S10_LATEST AS
    SELECT h.*, d.ID_MEDICAID AS LKP_ID_MEDICAID
      FROM STG_ECI_H_MEDICAID h
     INNER JOIN (SELECT m.ID_MEDICAID, MAX(m.LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_MEDICAID m
                  INNER JOIN STG_ECI_SN_CASE c ON m.ID_CASE = c.ID_CASE
                  WHERE c.ID_CHILD IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_CHILD')
                  GROUP BY m.ID_MEDICAID) mx
             ON mx.ID_MEDICAID = h.ID_MEDICAID AND mx.MAX_LOAD_DATE = h.LOAD_DATE
      LEFT JOIN (SELECT DISTINCT ID_MEDICAID FROM STG_ECI_D_MEDICAID) d ON d.ID_MEDICAID = h.ID_MEDICAID;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_RFM_S10_LATEST;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'LATEST_HISTORY_ROWS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_RFM_S10_LATEST', 'CREATED',
        'Latest history row per Medicaid record of reactivated children, with the delta-table '
        || 'lookup key. Read by the keep-new filter.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 LATEST_HISTORY_ROWS', :l_rows) || CHR(10);

    -- ---- Step 20: KEEP-NEW FILTER + ONE ROW PER ID ------------------------
    -- Purpose: the keep-new filter and the one-row-per-Medicaid-id
    -- rank. Reads ONLY step 10, so the lookup sees the delta table as
    -- it was before this run's publish, exactly as in the original.
    -- With the default parameter ('N') the filter tests the source
    -- ID_MEDICAID, which is never NULL, so this step is empty -- that
    -- is the preserved IDQ defect, not a bug in this rewrite.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_RFM_S20_KEEPNEW AS
    SELECT h.*
      FROM WRK_ECI_RFM_S10_LATEST h
     WHERE IFF(:P_TEST_LOOKUP_RESULT = 'Y', h.LKP_ID_MEDICAID IS NULL, h.ID_MEDICAID IS NULL)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY h.ID_MEDICAID ORDER BY h.DATE_MODIFIED DESC NULLS LAST) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_RFM_S20_KEEPNEW;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'KEEP_NEW_ONLY', 'COMPLETED', 'STG_ECI_D_MEDICAID', :l_rows, NULL,
        'WRK_ECI_RFM_S20_KEEPNEW', 'CREATED',
        'Rows passing the keep-new filter, one row per Medicaid id. Empty with the default '
        || 'parameter value (preserved defect); pass Y to keep records not yet in the delta table. '
        || 'Published in step 30.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 KEEP_NEW_ONLY', :l_rows) || CHR(10);

    -- ---- Step 30: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction. The INSERT below is the
    -- original INSERT, with the source changed from the history join
    -- to step 20. No TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    INSERT INTO STG_ECI_D_MEDICAID
           (ID_MEDICAID, ID_CASE, MEDICAID_NBR, ELIG_DATE, END_DATE, CURRENT_IND, CANCEL_DATE, HMO_DESC,
            DATE_CREATED, DATE_MODIFIED, MODIFIED_BY, CREATED_BY, CONSENT_TO_BILL, LOAD_DATE)
    SELECT h.ID_MEDICAID, h.ID_CASE, h.MEDICAID_NBR, h.ELIG_DATE, h.END_DATE, h.CURRENT_IND, h.CANCEL_DATE,
           h.HMO_DESC, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CONSENT_TO_BILL, h.LOAD_DATE
      FROM WRK_ECI_RFM_S20_KEEPNEW h;
    l_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'PUBLISH', 'COMPLETED', 'STG_ECI_D_MEDICAID', :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: latest history Medicaid rows of reactivated children '
        || 'into the delta table. Count shown is rows inserted (0 with the default parameter).');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail('ECI', :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
