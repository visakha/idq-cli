-- ============================================================================
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
--   --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Moves the latest history row of each phone record of a reactivated
--   family into the delta table. Phone records already in the delta
--   table are skipped.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement (history join to the latest-load
--   subquery, plus the keep-new filter), one transaction, one log line.
--   This rewrite splits that single statement at its natural boundary
--   into two staged steps plus publish. No business expression was
--   changed. FLAG: this original has no CTE chain, so the split below
--   is the closest sensible split (latest rows, then keep-new filter,
--   then publish), not a CTE-boundary split.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_RFP_S10_LATEST   latest history row per phone
--                                     record of reactivated families
--   Step 20  WRK_ECI_RFP_S20_KEEPNEW  latest rows not already in the
--                                     delta table
--   Step 30  PUBLISH                STG_ECI_D_FAMILY_PHONE, in one
--                                     transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_RFP_S10_LATEST, WRK_ECI_RFP_S20_KEEPNEW. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Rows already in the delta table are skipped
--     (the keep-new filter); the filter reads the delta table as it
--     was before the publish, because it is evaluated in step 20,
--     before any insert happens.
--   * No validation rule runs here; preserved.
--
-- SIGNATURE
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'ECI';
    c_workflow   VARCHAR DEFAULT 'wf_ECI_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn';
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
    DROP TABLE IF EXISTS WRK_ECI_RFP_S10_LATEST;
    DROP TABLE IF EXISTS WRK_ECI_RFP_S20_KEEPNEW;

    -- ---- Step 10: LATEST HISTORY ROWS ------------------------------------
    -- Purpose: the latest-load history row of each phone record
    -- belonging to a reactivated family. This is the history-to-latest
    -- join of the original INSERT (the source filter).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_RFP_S10_LATEST AS
    SELECT h.*
      FROM STG_ECI_H_FAMILY_PHONE h
     INNER JOIN (SELECT ID_FAMILY_PHONE, MAX(LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_FAMILY_PHONE
                  WHERE ID_FAMILY IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_FAMILY')
                  GROUP BY ID_FAMILY_PHONE) m
             ON m.ID_FAMILY_PHONE = h.ID_FAMILY_PHONE AND m.MAX_LOAD_DATE = h.LOAD_DATE;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_RFP_S10_LATEST;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'LATEST_HISTORY_ROWS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_RFP_S10_LATEST', 'CREATED',
        'Latest history row per phone record of reactivated families. Read by the keep-new filter.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 LATEST_HISTORY_ROWS', :l_rows) || CHR(10);

    -- ---- Step 20: KEEP-NEW FILTER -----------------------------------------
    -- Purpose: drop rows already in the delta table. Reads ONLY step
    -- 10, so the filter sees the delta table as it was before this
    -- run's publish, exactly as in the original. This is the original
    -- lookup plus keep-new filter.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_RFP_S20_KEEPNEW AS
    SELECT h.*
      FROM WRK_ECI_RFP_S10_LATEST h
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_D_FAMILY_PHONE d
                        WHERE d.ID_FAMILY_PHONE = h.ID_FAMILY_PHONE);
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_RFP_S20_KEEPNEW;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'KEEP_NEW_ONLY', 'COMPLETED', 'STG_ECI_D_FAMILY_PHONE', :l_rows, NULL,
        'WRK_ECI_RFP_S20_KEEPNEW', 'CREATED',
        'Latest rows not already in the delta table. Published in step 30.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 KEEP_NEW_ONLY', :l_rows) || CHR(10);

    -- ---- Step 30: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction. The INSERT below is the
    -- original INSERT, with the source changed from the history join
    -- to step 20. No TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    INSERT INTO STG_ECI_D_FAMILY_PHONE
           (ID_FAMILY_PHONE, ID_FAMILY, ID_CASE, HOME_AC, HOME_NBR, WORK_AC, WORK_NBR, WORK_EXT, CELL_AC, CELL_NBR,
            FAX_AC, FAX_NBR, PAGER_AC, PAGER_NBR, OTHER_AC, OTHER_NBR, EMAIL_ADDRESS, DATE_CREATED, DATE_MODIFIED,
            MODIFIED_BY, CREATED_BY, CHILD_RESIDES_IND, INACTIVE_IND, PRIMARY_CONTACT_IND, LOAD_DATE)
    SELECT h.ID_FAMILY_PHONE, h.ID_FAMILY, h.ID_CASE, h.HOME_AC, h.HOME_NBR, h.WORK_AC, h.WORK_NBR, h.WORK_EXT,
           h.CELL_AC, h.CELL_NBR, h.FAX_AC, h.FAX_NBR, h.PAGER_AC, h.PAGER_NBR, h.OTHER_AC, h.OTHER_NBR,
           h.EMAIL_ADDRESS, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CHILD_RESIDES_IND,
           h.INACTIVE_IND, h.PRIMARY_CONTACT_IND, h.LOAD_DATE
      FROM WRK_ECI_RFP_S20_KEEPNEW h;
    l_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'PUBLISH', 'COMPLETED', 'STG_ECI_D_FAMILY_PHONE', :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: latest history phone rows of reactivated families '
        || 'into the delta table. Count shown is rows inserted.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
