-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation  --  MODULAR REWRITE
--
-- Original: IDQ mapping m_Tgt_C_S_WIC_Pty_Validation, workflow
-- wf_WIC_Stage_Load (first step in the run order). Original Snowflake
-- procedure sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.
--
-- What this mapping does, in plain words: it checks the WIC parties in
-- V_WIC_ETL_SRC and maintains the deactivation list every later WIC
-- mapping reads. A party whose standardised first or last name is blank
-- is logged as an invalid-party-name exception, written to the
-- deactivation log, and given a new deactivation-status row if it has
-- none yet. A party that already has a status and now has both names
-- present is written to the deactivation log as a reactivation.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (sts / xref /
--   enriched -> named -> routed -> final SELECT), one transaction, one
--   log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   The status and cross-reference lookups (sts / xref) are reference
--   lookups, not data stages, so they stay inline in step 10 with the
--   enrichment that reads them.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_WIC_VAL_S10_ENRICHED  source parties enriched with the
--                                     current deactivation status, the
--                                     cross-reference hub state, and
--                                     standardised names
--   Step 20  WRK_WIC_VAL_S20_NAMED     standardised names pulled out +
--                                     the blank-name (name_missing) test
--   Step 30  WRK_WIC_VAL_S30_ROUTED    routing: exception code / attribute
--                                     + new deactivation status, exception
--                                     description and type resolved, and
--                                     the first-row-per-exception-key
--                                     flag (uq_exc_name)
--   Step 40  PUBLISH                  targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_WIC_VAL_S10_ENRICHED, WRK_WIC_VAL_S20_NAMED,
--   WRK_WIC_VAL_S30_ROUTED. They live in the same schema as the targets
--   (unqualified names, as in the original code), are prefixed WRK_WIC_,
--   and are registered in JOB_CONTROL_ETL at creation. They survive a
--   session crash (TRANSIENT, not TEMP), which is what makes inspection
--   after a run possible. A Snowflake CURSOR was NOT used: cursors
--   process row by row, and every step here is set-based by design --
--   the work table IS the result set, held as a table instead of in
--   memory, so it can be counted and inspected after the run.
--
-- INSTALL LOCATION
--   Install schema is WIC_ETL_WRK in database MDM_ETL_WIC. All table
--   names in the code below are unqualified, exactly as in the original.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ delete of STG_WIC_PTY_INACTIVE_STS
--     (the reactivation delete step) is NOT performed, exactly as in
--     the original Snowflake code -- rows are only inserted.
--   * PRESERVED: the exception row writes the computed code
--     (Missing_First_Name / Missing_Last_Name) with the looked-up
--     description and type from the exception lookup.
--   * PRESERVED: the cross-reference lookup filters on
--     TRIM(ROWID_SYSTEM) = 'WIC' (the MDM column is blank-padded).
--   * PRESERVED: step 30 (and therefore the publish) is computed
--     before any publish INSERT runs, so all routing sees the
--     pre-run deactivation status -- the same snapshot behaviour as
--     the original single INSERT ALL.
--   * PRESERVED: there is no timeline handling in this mapping
--     (no VERSION_SEQ), exactly as in the original.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Validation';
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
    DROP TABLE IF EXISTS WRK_WIC_VAL_S10_ENRICHED;
    DROP TABLE IF EXISTS WRK_WIC_VAL_S20_NAMED;
    DROP TABLE IF EXISTS WRK_WIC_VAL_S30_ROUTED;

    -- ---- Step 10: ENRICH -- source + status + cross-reference + standardised names
    -- Purpose: every source party, joined to its current deactivation
    -- status (latest row per source key) and its cross-reference hub
    -- state, with standardised names computed. This is the only step
    -- that reads V_WIC_ETL_SRC; every later step reads work tables.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_VAL_S10_ENRICHED AS
    WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (    -- Lookup_STG_WIC_PTY_INACTIVE_STS (any row)
        SELECT i.SRC_KEY, i.DEACTIVATION_STS
          FROM STG_WIC_PTY_INACTIVE_STS i
         WHERE i.ROWID_SYSTEM = 'WIC'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
    ),
    xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'WIC')
        SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'WIC'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
    )
    SELECT v.SOURCE_TABLE, v.ID, v.FIRST_NAME, v.LAST_NAME, v.MIDDLE_NAME, v.DOB, v.DATEKEY, v.LOAD_DATE,
           v.PTY_SRC_KEY,
           sts.DEACTIVATION_STS AS deactivation_sts,
           xref.HUB_STATE_IND   AS hub_state_ind,
           fn_snow_helper15_common(v.FIRST_NAME, v.MIDDLE_NAME, v.LAST_NAME,
               TRIM(NVL(v.FIRST_NAME, '') || IFF(v.MIDDLE_NAME IS NOT NULL, ' ' || TRIM(v.MIDDLE_NAME), '')
                    || ' ' || NVL(LTRIM(v.LAST_NAME), '')),
               NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
      FROM V_WIC_ETL_SRC v
      LEFT JOIN sts  ON sts.SRC_KEY = v.PTY_SRC_KEY
      LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = v.PTY_SRC_KEY
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(v.FIRST_NAME)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(v.LAST_NAME)) AND jl.IS_LAST_JUNK;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_VAL_S10_ENRICHED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ENRICHED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_VAL_S10_ENRICHED', 'CREATED',
        'Source parties joined to the current deactivation status and cross-reference hub state, '
        || 'with standardised names computed. Read by the blank-name test step.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ENRICHED', :l_rows) || CHR(10);

    -- ---- Step 20: NAMED -- standardised names + blank-name test ----------
    -- Purpose: pull the standardised first / middle / last names out of
    -- the name object and apply the blank test: a party is
    -- name_missing when its standardised first name OR its
    -- standardised last name is blank.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_VAL_S20_NAMED AS
    SELECT n.*,
           n.nm:first_name::VARCHAR  AS std_first_name,
           n.nm:middle_name::VARCHAR AS std_mdl_name,
           n.nm:last_name::VARCHAR   AS std_lst_name,
           /* VALIDATION */ (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                             OR fn_snow_helper03_common(n.nm:last_name::VARCHAR)) AS name_missing
      FROM WRK_WIC_VAL_S10_ENRICHED n;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_VAL_S20_NAMED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'NAMED_BLANK_TEST', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_VAL_S20_NAMED', 'CREATED',
        'Standardised names pulled out, with the blank-name test applied (name_missing). '
        || 'Read by the routing step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 NAMED_BLANK_TEST', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTED -- exception details + deactivation status ------
    -- Purpose: the routed rows that publish will write. Name-missing
    -- rows get their exception code (first name checked first) and
    -- attribute name / value; every row gets its new deactivation
    -- status derived from its hub state, plus the looked-up exception
    -- description and type, the run constants, and the
    -- first-row-per-exception-key flag (uq_exc_name).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_VAL_S30_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    routed AS (
        SELECT r.*,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name' END  AS exc_code_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'First Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Last Name' END          AS exc_attribute_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN r.std_first_name
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN r.std_lst_name END       AS exc_attribute_value,
               fn_snow_helper02_common(r.hub_state_ind)                                        AS new_deactivation_sts
          FROM WRK_WIC_VAL_S20_NAMED r
    )
    SELECT r.*,
           ex.EXCEPTION_DESC     AS exc_desc_name,
           ex.EXCEPTION_TYPE     AS exc_type_name,
           'WIC'                 AS src_sys,
           :l_run_ts             AS run_ts,
           :c_mapping            AS mapping_name,
           'Deactivation'        AS action_deactivation,
           'Reactivation'        AS action_reactivation,
           /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
           ROW_NUMBER() OVER (PARTITION BY r.name_missing, r.PTY_SRC_KEY, ex.EXCEPTION_TYPE, r.exc_code_name
                                  ORDER BY r.DATEKEY DESC, r.ID) = 1 AS uq_exc_name
      FROM routed r
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_VAL_S30_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_VAL_S30_ROUTED', 'CREATED',
        'Routed rows: exception code / attribute for name-missing parties, new deactivation status, '
        || 'looked-up exception description and type, and the first-row-per-exception-key flag (uq_exc_name). '
        || 'Read by the publish step; computed before publish, so routing sees the pre-run status.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 40: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-30 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning. The four INSERTs below are the
    -- four branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHEN conditions -- only the
    -- source changed, from the original query to step 30.
    BEGIN TRANSACTION;
    -- 40a. Invalid_Party_Name -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, FIRST_NAME, MIDDLE_NAME,
            LAST_NAME, RUN_DATE, SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE,
            BIRTH_DATE)
    SELECT DATEKEY, mapping_name, exc_attribute_name, exc_attribute_value, std_first_name, std_mdl_name,
           std_lst_name, run_ts, src_sys, PTY_SRC_KEY, exc_desc_name, exc_type_name, exc_code_name, DOB
      FROM WRK_WIC_VAL_S30_ROUTED
     WHERE name_missing AND uq_exc_name;
    -- 40b. Deactivation -> STG_WIC_PTY_INACTIVE_LOG
    INSERT INTO STG_WIC_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT PTY_SRC_KEY, src_sys, action_deactivation, run_ts
      FROM WRK_WIC_VAL_S30_ROUTED
     WHERE name_missing;
    -- 40c. New deactivations -> STG_WIC_PTY_INACTIVE_STS
    INSERT INTO STG_WIC_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT PTY_SRC_KEY, src_sys, new_deactivation_sts, run_ts
      FROM WRK_WIC_VAL_S30_ROUTED
     WHERE name_missing AND deactivation_sts IS NULL;
    -- 40d. Reactivation -> STG_WIC_PTY_INACTIVE_LOG
    INSERT INTO STG_WIC_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT PTY_SRC_KEY, src_sys, action_reactivation, run_ts
      FROM WRK_WIC_VAL_S30_ROUTED
     WHERE deactivation_sts IS NOT NULL AND NOT name_missing;
    COMMIT;
    -- Publish row counts by branch are not summed here; report the
    -- routed-row count that fed the publish instead.
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_VAL_S30_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PUBLISH', 'COMPLETED',
        'EXC_STG_BAD_REC_MEMB, STG_WIC_PTY_INACTIVE_LOG, STG_WIC_PTY_INACTIVE_STS',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: invalid-name exceptions, deactivation log rows, new deactivation '
        || 'status rows, and reactivation log rows. Count shown is routed rows feeding the publish; '
        || 'each branch inserts only its own WHEN-filtered subset.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PUBLISH (routed rows)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_WIC_Pty_Validation completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_WIC_Pty_Validation failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
