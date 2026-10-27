-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id  --  MODULAR REWRITE
--
-- Original: IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Alt_Id, workflow
-- wf_WIC_Stage_Load. Original Snowflake procedure
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.
--
-- What this mapping does, in plain words: it writes one alternate id
-- per active WIC party into C_S_WIC_PTY_RLE_ALT_ID -- the WIC id padded
-- to 12, type '020' for SOURCE_TABLE 'CLIENT' and '021' otherwise. A
-- party with a deactivation status is excluded, and a key already in
-- the target is skipped.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one single-level query (an inner
--   derived table building the keys, plus the deactivation filter, the
--   already-loaded guard and a one-row-per-key rank in the outer
--   SELECT), one transaction, one log line at the end.
--   This rewrite: the SAME business SQL, split into the closest
--   sensible staged steps (see the SPLIT NOTE below). No business
--   expression was changed. The publish is the original INSERT,
--   written as a single INSERT from the last work table inside ONE
--   transaction.
--
-- SPLIT NOTE (flagged, not hidden): this original has no CTE chain to
-- split at -- it is a single query. The split used here is:
--   step 10 builds the keys (the original inner derived table);
--   step 20 applies the deactivation filter, the already-loaded guard
--   and the one-row-per-key rank (the original outer SELECT).
-- Merging everything into a single step would have hidden the
-- key-building stage, so the two-step split is kept even though the
-- stages are thin.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_WIC_ALT_S10_KEYS   alternate-id keys: party-role key,
--                                   id type ('020' / '021') and the
--                                   alternate-id key itself
--   Step 20  WRK_WIC_ALT_S20_READY  deactivation filter + already-loaded
--                                   guard + one row per key (latest
--                                   DATEKEY wins)
--   Step 30  PUBLISH                target, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_WIC_ALT_S10_KEYS, WRK_WIC_ALT_S20_READY. They live in the same
--   schema as the targets (unqualified names, as in the original code),
--   are prefixed WRK_WIC_, and are registered in JOB_CONTROL_ETL at
--   creation. They survive a session crash (TRANSIENT, not TEMP), which
--   is what makes inspection after a run possible. A Snowflake CURSOR
--   was NOT used: cursors process row by row, and every step here is
--   set-based by design -- the work table IS the result set, held as a
--   table instead of in memory, so it can be counted and inspected
--   after the run.
--
-- INSTALL LOCATION
--   Install schema is WIC_ETL_WRK in database MDM_ETL_WIC. All table
--   names in the code below are unqualified, exactly as in the original.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ truncate of C_S_WIC_PTY_RLE_ALT_ID
--     is NOT performed; instead keys already present are skipped.
--   * PRESERVED: HUB_STATE_IND is not linked in this mapping (left to
--     the column default), exactly as in the original.
--   * PRESERVED: VERSION_SEQ = 1 and PERIOD_START_DATE = DATEKEY.
--   * PRESERVED: the already-loaded guard is evaluated in step 20,
--     before the publish transaction, against the target as it stands
--     at that point -- the same snapshot behaviour as the original
--     single INSERT, whose source query was evaluated once before
--     inserting.
--   * No validation rule runs in this mapping, exactly as in the
--     original.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order (this
--   mapping has none), so every existing CALL still works. One
--   parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'WIC';
    c_workflow   VARCHAR DEFAULT 'wf_WIC_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id';
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
            'WIC_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_WIC_ALT_S10_KEYS;
    DROP TABLE IF EXISTS WRK_WIC_ALT_S20_READY;

    -- ---- Step 10: KEYS -- alternate-id keys ------------------------------
    -- Purpose: the original inner derived table, verbatim -- one row
    -- per source row with its party-role key, its id type ('020' for
    -- SOURCE_TABLE 'CLIENT', '021' otherwise) and its alternate-id
    -- key (party key + role + type + 12-padded id). This is the only
    -- step that reads V_WIC_ETL_SRC; every later step reads work tables.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_ALT_S10_KEYS AS
    SELECT v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.SOURCE_TABLE,
           NVL(v.PTY_SRC_KEY, '') || '|Member'                                    AS pty_rle_fk,
           IFF(v.SOURCE_TABLE = 'CLIENT', '020', '021')                           AS alt_id_tp,
           NVL(v.PTY_SRC_KEY, '') || '|Member|' || IFF(v.SOURCE_TABLE = 'CLIENT', '020', '021') || '|'
           || NVL(LPAD(TO_VARCHAR(v.ID), 12, '0'), '')                             AS pkey_src_object
      FROM V_WIC_ETL_SRC v;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ALT_S10_KEYS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'KEYS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_ALT_S10_KEYS', 'CREATED',
        'Alternate-id keys for every source row: party-role key, id type (020 for CLIENT, 021 otherwise), '
        || 'and the alternate-id key itself. Read by the filter / guard step.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 KEYS', :l_rows) || CHR(10);

    -- ---- Step 20: READY -- deactivation filter + guard + one row per key -
    -- Purpose: the original outer SELECT, verbatim -- drop parties with
    -- a deactivation status, drop keys already in the target, and keep
    -- one row per alternate-id key (latest DATEKEY wins). Reads ONLY
    -- step 10 (plus the target guard lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_ALT_S20_READY AS
    SELECT x.*
      FROM WRK_WIC_ALT_S10_KEYS x
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = x.pkey_src_object
     -- Lookup_STG_WIC_PTY_INACTIVE_STS + Filter
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = x.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       /* BAD DATA: unique key not yet in the table, first row per key in this run */
       AND xa.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x.pkey_src_object ORDER BY x.DATEKEY DESC NULLS LAST) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ALT_S20_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'READY', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_ALT_S20_READY', 'CREATED',
        'Ready rows: deactivation filter applied, keys already in the target skipped, one row per '
        || 'alternate-id key (latest DATEKEY wins). Read by the publish step; the guard is evaluated '
        || 'here, before publish, as in the original single query.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 READY', :l_rows) || CHR(10);

    -- ---- Step 30: PUBLISH -- one transaction, one target -----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction. If the INSERT fails, the
    -- publish rolls back, the checkpoints for steps 10-20 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning. The INSERT below is the original
    -- INSERT, with the same column list and values -- only the source
    -- changed, from the original query to step 20.
    BEGIN TRANSACTION;
    INSERT INTO C_S_WIC_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE,
            ALT_ID_TP_FLTR, SRC_LAST_UPD_DT, STS_CD, PERIOD_START_DATE)
    SELECT x.pkey_src_object, NVL(TO_VARCHAR(x.ID), '') || '|' || x.alt_id_tp, 1 /* TIMELINE: VERSION_SEQ */,
           x.pty_rle_fk, x.alt_id_tp, LPAD(TO_VARCHAR(x.ID), 12, '0'), x.DATEKEY, :l_run_ts, x.alt_id_tp,
           x.DATEKEY /* IIF(IsNull(DATEKEY), DATEKEY, DATEKEY) */, 'Issued', x.DATEKEY /* TIMELINE */
      FROM WRK_WIC_ALT_S20_READY x;
    COMMIT;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ALT_S20_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'PUBLISH', 'COMPLETED',
        'C_S_WIC_PTY_RLE_ALT_ID',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: one alternate id per active party into C_S_WIC_PTY_RLE_ALT_ID. '
        || 'Count shown is ready rows feeding the publish; every ready row inserts, since the filters '
        || 'and guard were already applied in step 20.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 PUBLISH (ready rows)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        -- Roll back the publish transaction if one is open (harmless if
        -- none is), then write the FAILED terminating row -- AFTER the
        -- rollback, so it is NOT rolled back. Work tables are NOT
        -- dropped here: that is the whole point of KEPT. The caller
        -- (workflow runner) will see the raise and stop the workflow;
        -- the operator restarts the mapping with a new run.
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
