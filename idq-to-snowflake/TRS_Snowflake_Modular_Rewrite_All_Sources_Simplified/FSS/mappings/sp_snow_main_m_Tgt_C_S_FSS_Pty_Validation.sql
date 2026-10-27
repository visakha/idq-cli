-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty_Validation, workflow wf_FSS_Stage_Load
-- (first step of the workflow).
--
-- What this mapping does, in plain words: it checks the FSS clients in
-- V_FSS_ETL_SRC (rows that are the last active registration of a client
-- or that mark all registrations inactive) and maintains the
-- deactivation list every later FSS mapping reads. Clients whose
-- standardised first or last name is blank are written as exception
-- rows; clients that are blank-named, deleted, or all-inactive are
-- written to the deactivation log and get a new deactivation status row
-- when they have no status yet; clients that have a status, have names,
-- are not deleted and are not all-inactive get a reactivation status
-- row. Rows that fit none of these groups are not linked anywhere.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> sts /
--   xref -> enriched -> named -> routed -> final), one transaction,
--   one log line at the end.  If it failed, nothing told you which
--   logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   No step before publish writes to a final target, so the target
--   reads in later steps (deactivation status, cross-reference) still
--   see the same target state as the original single statement did.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_FSS_VAL_S1_SRC       source clients (last active or
--                                     all-inactive registration)
--   Step 20  WRK_FSS_VAL_S2_ENRICHED  standardised names + blank-name
--                                     flag, with current deactivation
--                                     status and cross-reference state
--   Step 30  WRK_FSS_VAL_S3_ROUTED    routed groups (invalid name /
--                                     deactivation / reactivation),
--                                     exception details, first-row
--                                     flag for the exception key
--   Step 50  PUBLISH                  targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_FSS_VAL_S1_SRC, WRK_FSS_VAL_S2_ENRICHED, WRK_FSS_VAL_S3_ROUTED.
--   They live in the same schema as the targets (unqualified names, as
--   in the original code), are prefixed WRK_FSS_, and are registered in
--   the shared job-control table at creation.  They survive a session
--   crash (TRANSIENT, not TEMP), which is what makes inspection after
--   a run possible.  A Snowflake CURSOR was NOT used: cursors process
--   row by row, and every step here is set-based by design -- the work
--   table IS the result set, held as a table instead of in memory, so
--   it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  The IDQ delete of STG_FSS_PTY_INACTIVE_STS
--     for reactivations is NOT performed, exactly as in the original.
--   * PRESERVED: the reactivation branch writes its row to
--     STG_FSS_PTY_INACTIVE_STS (the status table), not to the log
--     table, as ported from the original.  Because later mappings skip
--     any key with a non-null status, a reactivated FSS client stays
--     excluded -- confirm with the business.
--   * PRESERVED: a NULL capture action or inactive flag is not treated
--     as "not deleted / not inactive" (a NULL comparison is not true),
--     so such rows are not reactivated.
--   * PRESERVED: the commented-out testing source filters are not
--     applied, exactly as in the original.
--   * The exception row writes the computed code with the looked-up
--     description / type, and the source full name as the attribute
--     value, exactly as in the original.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Validation';
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
    DROP TABLE IF EXISTS WRK_FSS_VAL_S1_SRC;
    DROP TABLE IF EXISTS WRK_FSS_VAL_S2_ENRICHED;
    DROP TABLE IF EXISTS WRK_FSS_VAL_S3_ROUTED;

    -- ---- Step 10: SOURCE --------------------------------------------------
    -- Purpose: the FSS clients to check -- rows that are the last active
    -- registration of a client or that mark all registrations inactive.
    -- Every later step reads this table, never the raw source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_VAL_S1_SRC AS
    SELECT v.ID_CLIENT, v.PTY_SRC_KEY, v.SOURCE_TYPE, v.NM_FIRST, v.NM_LAST, v.NM_MIDDLE, v.DT_DOB,
           v.DT_LAST_UPDATE, v.CLIENT_DTL__CAPXACTION, v.STG_UPDATE_DATE, v.LAST_INACTV_CLIENT_YN
      FROM V_FSS_ETL_SRC v
     WHERE (v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y' OR v.LAST_INACTV_CLIENT_YN = 'Y');
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_VAL_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_VAL_S1_SRC', 'CREATED',
        'Source clients to check: last active registration or all-inactive rows. '
        || 'Read by the enrichment step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC', :l_rows) || CHR(10);

    -- ---- Step 20: ENRICH + STANDARDISE NAMES ------------------------------
    -- Purpose: standardise each client's names, flag blank first or last
    -- names, and attach the client's current deactivation status and
    -- cross-reference state.  Reads ONLY WRK_FSS_VAL_S1_SRC (plus the
    -- reference lookups and the status / cross-reference tables).
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_VAL_S2_ENRICHED AS
    WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (    -- Lookup_STG_FSS_PTY_INACTIVE_STS (any row)
        SELECT i.SRC_KEY, i.DEACTIVATION_STS
          FROM STG_FSS_PTY_INACTIVE_STS i
         WHERE i.ROWID_SYSTEM = 'FSS'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
    ),
    xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'FSS'; blank-padded MDM column trimmed)
        SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'FSS'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
    ),
    enriched AS (
        SELECT s.*,
               sts.DEACTIVATION_STS AS deactivation_sts,
               xref.HUB_STATE_IND   AS hub_state_ind,
               fn_snow_helper15_common(s.NM_FIRST, s.NM_MIDDLE, s.NM_LAST,
                   TRIM(NVL(s.NM_FIRST, '') || IFF(s.NM_MIDDLE IS NOT NULL, ' ' || TRIM(s.NM_MIDDLE), '')
                        || ' ' || NVL(LTRIM(s.NM_LAST), '')),
                   NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
          FROM WRK_FSS_VAL_S1_SRC s
          LEFT JOIN sts  ON sts.SRC_KEY = s.PTY_SRC_KEY
          LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = s.PTY_SRC_KEY
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(s.NM_FIRST)) AND jf.IS_FIRST_JUNK
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(s.NM_LAST)) AND jl.IS_LAST_JUNK
    )
    SELECT n.*,
           n.nm:first_name::VARCHAR    AS std_first_name,
           n.nm:middle_name::VARCHAR   AS std_mdl_name,
           n.nm:last_name::VARCHAR     AS std_lst_name,
           n.nm:src_full_name::VARCHAR AS std_src_full_name,
           /* VALIDATION */ (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                             OR fn_snow_helper03_common(n.nm:last_name::VARCHAR)) AS name_missing
      FROM enriched n;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_VAL_S2_ENRICHED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'ENRICHED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_VAL_S2_ENRICHED', 'CREATED',
        'Standardised names with the blank-name flag, plus current deactivation status and cross-reference state. '
        || 'Read by the router step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 ENRICHED', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTE ----------------------------------------------------
    -- Purpose: put every client into its groups -- invalid party name,
    -- deactivation, reactivation -- resolve the exception code /
    -- attribute for blank names, derive the new deactivation status
    -- from the hub state, and flag the first row per exception key.
    -- This is the only table step 50 reads.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_VAL_S3_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    routed AS (
        SELECT r.*,
               r.name_missing                                                          AS grp_invalid_party_name,
               (r.name_missing OR r.CLIENT_DTL__CAPXACTION = 'D' OR r.LAST_INACTV_CLIENT_YN = 'Y') AS grp_deactivation,
               NVL(r.deactivation_sts IS NOT NULL AND NOT r.name_missing
                   AND r.CLIENT_DTL__CAPXACTION <> 'D' AND r.LAST_INACTV_CLIENT_YN <> 'Y', FALSE) AS grp_reactivation,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name' END    AS exc_code_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'First Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Last Name' END            AS exc_attribute_name,
               fn_snow_helper02_common(r.hub_state_ind)                                          AS new_deactivation_sts
          FROM WRK_FSS_VAL_S2_ENRICHED r
    )
    SELECT r.*,
           ex.EXCEPTION_DESC     AS exc_desc_name,
           ex.EXCEPTION_TYPE     AS exc_type_name,
           'FSS'                 AS src_sys,
           :l_run_ts             AS run_ts,
           :c_mapping            AS mapping_name,
           'Deactivation'        AS action_deactivation,
           'Reactivation'        AS action_reactivation,
           /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
           ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.PTY_SRC_KEY, ex.EXCEPTION_TYPE,
                                           r.exc_code_name ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1 AS uq_exc_name
      FROM routed r
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_VAL_S3_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_VAL_S3_ROUTED', 'CREATED',
        'Routed groups (invalid name / deactivation / reactivation) with exception details and the first-row-per-exception-key flag. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-30 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The four INSERTs below are the four branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final CTE to step 30.  A row can land in more
    -- than one branch, exactly as in INSERT ALL.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 50a. Invalid party name -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, RUN_DATE,
            SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE, BIRTH_DATE, ATTRIBUTE_VALUE)
    SELECT DT_LAST_UPDATE, mapping_name, exc_attribute_name, std_first_name, std_mdl_name, std_lst_name,
           run_ts, src_sys, PTY_SRC_KEY, exc_desc_name, exc_type_name, exc_code_name, DT_DOB,
           std_src_full_name
      FROM WRK_FSS_VAL_S3_ROUTED
     WHERE grp_invalid_party_name AND uq_exc_name;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50b. Deactivation -> STG_FSS_PTY_INACTIVE_LOG
    INSERT INTO STG_FSS_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT PTY_SRC_KEY, src_sys, action_deactivation, run_ts
      FROM WRK_FSS_VAL_S3_ROUTED
     WHERE grp_deactivation;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50c. New deactivations -> STG_FSS_PTY_INACTIVE_STS
    INSERT INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT PTY_SRC_KEY, src_sys, new_deactivation_sts, run_ts
      FROM WRK_FSS_VAL_S3_ROUTED
     WHERE grp_deactivation AND deactivation_sts IS NULL;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50d. Reactivation -> STG_FSS_PTY_INACTIVE_STS
    INSERT INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT PTY_SRC_KEY, src_sys, action_reactivation, run_ts
      FROM WRK_FSS_VAL_S3_ROUTED
     WHERE grp_reactivation;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'EXC_STG_BAD_REC_MEMB, STG_FSS_PTY_INACTIVE_LOG, STG_FSS_PTY_INACTIVE_STS',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: invalid-name exceptions, deactivation log rows, new deactivation statuses and reactivation statuses. '
        || 'Count shown is the total rows inserted by all four INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_FSS_Pty_Validation completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_FSS_Pty_Validation failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
