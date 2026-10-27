-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty_Rle_Alt_Id, workflow wf_FSS_Stage_Load.
--
-- What this mapping does, in plain words: it writes one alternate ID
-- row per active FSS client into the role alternate-ID table -- the
-- FSS client ID, with type '022' for source type CLIENT and '023'
-- otherwise. Clients on the deactivation list are skipped, and keys
-- already in the target are skipped.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement over a keyed subquery with a
--   deactivation filter, a target-key guard and a first-row-per-key
--   ranking, one transaction, one log line at the end.  If it failed,
--   nothing told you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at its natural
--   boundaries into named work tables, one step at a time.  No
--   business expression was changed; the publish INSERT reads the
--   filtered work table instead of the original subquery.  The publish
--   is the only step inside an explicit transaction.
--   No step before publish writes to a final target, so the target
--   reads in the filtering step (keys already in the alternate-ID
--   table) still see the same target state as the original single
--   statement did.
--   NOTE ON THE SPLIT: this mapping has no CTE chain to split -- its
--   whole logic is one keyed query plus filters -- so it stages into
--   just two work tables (keyed source rows, then filtered rows)
--   before publish.  That is the closest sensible split; nothing was
--   merged into a single step to hide it.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_FSS_ALT_S1_SRC       keyed source rows: client ID,
--                                     role key, alternate-ID type and
--                                     key, for last active registrations
--   Step 20  WRK_FSS_ALT_S2_FILTERED  deactivated parties removed,
--                                     keys already in the target
--                                     removed, first row per key kept
--   Step 50  PUBLISH                  target, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_FSS_ALT_S1_SRC, WRK_FSS_ALT_S2_FILTERED.  They live in the
--   same schema as the targets (unqualified names, as in the original
--   code), are prefixed WRK_FSS_, and are registered in the shared
--   job-control table at creation.  They survive a session crash
--   (TRANSIENT, not TEMP), which is what makes inspection after a run
--   possible.  A Snowflake CURSOR was NOT used: cursors process row by
--   row, and every step here is set-based by design -- the work table
--   IS the result set, held as a table instead of in memory, so it can
--   be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  The IDQ truncate of the alternate-ID table
--     is NOT performed; keys already present are skipped instead.
--     A re-run therefore inserts nothing twice, but it also does not
--     remove rows that IDQ would have truncated away.
--   * PRESERVED: the commented-out testing source filter is not
--     applied, exactly as in the original.
--   * Version sequence is 1 and the period start date is the create
--     date, exactly as in the original.
--
-- INSTALL
--   Install schema is FSS_ETL_WRK in database MDM_ETL_FSS.  All table
--   names in the code below are unqualified, as in the original code.
--   Shared control calls (sp_etl_job_begin / sp_etl_checkpoint /
--   sp_etl_job_finish / sp_etl_job_fail) take SOURCE first and live in
--   the shared framework; shared helpers are fn_snow_helperNN_common.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order (this
--   mapping had none), so every existing CALL still works.  One
--   parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id (
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'FSS';
    c_workflow   VARCHAR DEFAULT 'wf_FSS_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Alt_Id';
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
            'FSS_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_FSS_ALT_S1_SRC;
    DROP TABLE IF EXISTS WRK_FSS_ALT_S2_FILTERED;

    -- ---- Step 10: KEYED SOURCE ---------------------------------------------
    -- Purpose: one keyed row per source row -- the role key, the
    -- alternate-ID type ('022' for CLIENT, '023' otherwise) and the
    -- alternate-ID key -- for last active registrations.  Every later
    -- step reads this table, never the raw source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_ALT_S1_SRC AS
    SELECT v.SOURCE_TYPE, v.DT_CREATED, v.DT_LAST_UPDATE, v.PTY_SRC_KEY, v.ID_CLIENT,
           NVL(v.PTY_SRC_KEY, '') || '|Member'                                      AS pty_rle_fk,
           IFF(v.SOURCE_TYPE = 'CLIENT', '022', '023')                              AS alt_id_tp,
           NVL(v.PTY_SRC_KEY, '') || '|Member|' || IFF(v.SOURCE_TYPE = 'CLIENT', '022', '023') || '|'
           || NVL(LPAD(TO_VARCHAR(v.ID_CLIENT), 10, '0'), '')                        AS pkey_src_object
      FROM V_FSS_ETL_SRC v
     -- source filter (the commented-out testing filter is not applied)
     WHERE v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y';
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_ALT_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_ALT_S1_SRC', 'CREATED',
        'Keyed source rows: role key, alternate-ID type and key, for last active registrations. '
        || 'Read by the filtering step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_KEYED', :l_rows) || CHR(10);

    -- ---- Step 20: FILTER -----------------------------------------------------
    -- Purpose: drop deactivated parties (any non-null deactivation
    -- status), drop keys already in the target, and keep the first row
    -- per alternate-ID key.  This is the only table step 50 reads.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_ALT_S2_FILTERED AS
    SELECT x.*
      FROM WRK_FSS_ALT_S1_SRC x
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = x.pkey_src_object
     -- Lkp_STG_FSS_PTY_INACTIVE_STS + Filter: IsNull(DEACTIVATION_STS)
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = x.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       /* BAD DATA: unique key not yet in the table */
       AND xa.PKEY_SRC_OBJECT IS NULL
    /* BAD DATA: first row per key in this run */
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x.pkey_src_object ORDER BY x.DT_LAST_UPDATE DESC NULLS LAST) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_ALT_S2_FILTERED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'FILTERED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_ALT_S2_FILTERED', 'CREATED',
        'Publish-ready rows: deactivated parties and existing keys removed, first row per key kept. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 FILTERED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, one target ------------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction.  If the INSERT fails, the
    -- publish rolls back, the checkpoints for steps 10-20 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The INSERT below is the original
    -- INSERT, with the same column list, values and source -- only the
    -- source changed, from the keyed subquery to step 20.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 50a. Alternate IDs -> C_S_FSS_PTY_RLE_ALT_ID
    INSERT INTO C_S_FSS_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, SRC_LAST_UPD_DT, HUB_STATE_IND, STS_CD, SRC_ROWID,
            LAST_UPDATE_DATE, VERSION_SEQ, ALT_ID_TP_FLTR, CREATE_DATE, PERIOD_START_DATE)
    SELECT x.pkey_src_object, x.pty_rle_fk, x.alt_id_tp, LPAD(TO_VARCHAR(x.ID_CLIENT), 10, '0'), :l_run_ts, 1,
           'Issued', NVL(TO_VARCHAR(x.ID_CLIENT), '') || '|' || x.alt_id_tp, :l_run_ts,
           1 /* TIMELINE: VERSION_SEQ */, x.alt_id_tp, x.DT_CREATED, x.DT_CREATED /* TIMELINE */
      FROM WRK_FSS_ALT_S2_FILTERED x;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_FSS_PTY_RLE_ALT_ID',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: one alternate-ID row per active client. '
        || 'Count shown is the rows inserted by the single INSERT.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_FSS_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_FSS_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
