-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation  --  MODULAR REWRITE (simplified v2 style)
--
-- IDQ mapping: m_Tgt_C_S_TTF_Pty_Validation, workflow wf_TTF_Stage_Load
-- (first mapping in the workflow run order).
--
-- Business flow, in plain words: read the TTF clients, standardise their
-- names, and maintain the deactivation list every later TTF mapping
-- relies on. Party key = LPAD(CLIENTS_ID, 10, '0').
--   * Invalid party name: first or last name blank, or 'DECLINED' /
--     'DO_NOT_DISCLOSE' -> one exception row in EXC_STG_BAD_REC_MEMB.
--   * Deactivation: name blank or 'DECLINED' (not 'DO_NOT_DISCLOSE'),
--     or CLIENT_EXISTS_FLAG = 'N' -> a 'Deactivation' row in
--     STG_TTF_PTY_INACTIVE_LOG, plus a new status row in
--     STG_TTF_PTY_INACTIVE_STS when the party has no status yet.
--   * Reactivation: party already has a status, names present and not
--     'DECLINED', CLIENT_EXISTS_FLAG = 'Y' -> a 'Reactivation' row in
--     STG_TTF_PTY_INACTIVE_LOG.
--   * Default group: not linked anywhere.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (sts -> xref ->
--   enriched -> named -> routed -> final), one transaction, one log
--   line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE transaction,
--   so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TTF_VAL_S1_ENRICHED  clients + latest inactive status +
--                                     cross-reference row + standardised
--                                     names
--   Step 20  WRK_TTF_VAL_S2_NAMED     standardised names pulled out +
--                                     blank / declined / undisclosed flags
--   Step 30  WRK_TTF_VAL_S3_ROUTED    router groups (invalid name /
--                                     deactivation / reactivation) +
--                                     exception code, description and
--                                     type + first-row-per-key flag
--   Step 40  PUBLISH                 targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_TTF_VAL_S1_ENRICHED, WRK_TTF_VAL_S2_NAMED, WRK_TTF_VAL_S3_ROUTED.
--   They live in the install schema (unqualified names, as in the
--   original code): schema TTF_ETL_WRK in database MDM_ETL_TTF.
--   They survive a session crash (TRANSIENT, not TEMP), which is what
--   makes inspection after a run possible.  No CURSOR was used: every
--   step here is set-based by design -- the work table IS the result
--   set, held as a table instead of in memory, so it can be counted
--   and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  PRESERVED: the IDQ DD_DELETE of
--     STG_TTF_PTY_INACTIVE_STS (Upd_Delete_Inactive) is NOT performed.
--   * PRESERVED: the source read stores a SQL text that is only a WHERE
--     fragment (test client ids) and is not in custom-query mode, so it
--     is not applied -- no such filter appears in this rewrite either.
--   * PRESERVED: a 'DO_NOT_DISCLOSE' name is logged as an exception
--     but does NOT deactivate the party (deactivation tests blank or
--     'DECLINED' only, plus CLIENT_EXISTS_FLAG = 'N').
--   * PRESERVED: the cross-reference lookup filter is
--     TRIM(ROWID_SYSTEM) = 'TTF' (the MDM column is blank padded).
--   * PRESERVED: the exception row writes the computed code, with
--     description / type from the exception lookup, and the source full
--     name as ATTRIBUTE_VALUE; the unique key of EXC_STG_BAD_REC_MEMB
--     is applied by the uq_exc_name flag, not enforced by Snowflake.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order (the
--   original took no parameters), so every existing CALL still works.
--   One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'TTF';
    c_workflow   VARCHAR DEFAULT 'wf_TTF_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty_Validation';
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
            'TTF_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_TTF_VAL_S1_ENRICHED;
    DROP TABLE IF EXISTS WRK_TTF_VAL_S2_NAMED;
    DROP TABLE IF EXISTS WRK_TTF_VAL_S3_ROUTED;

    -- ---- Step 10: ENRICH -- clients + status + cross-reference + names --
    -- Purpose: one row per TTF client, joined to its latest inactive
    -- status (if any) and its cross-reference row (if any), with the
    -- standardised name object attached.  Every later step reads this
    -- table, never the raw source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_VAL_S1_ENRICHED AS
    WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (    -- Lookup_STG_TTF_PTY_INACTIVE_STS (any row)
        SELECT i.SRC_KEY, i.DEACTIVATION_STS
          FROM STG_TTF_PTY_INACTIVE_STS i
         WHERE i.ROWID_SYSTEM = 'TTF'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
    ),
    xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter TRIM(ROWID_SYSTEM) = 'TTF')
        SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'TTF'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
    ),
    enriched AS (
        SELECT v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.CREATEDDATE, v.SUBMITDATE,
               v.CLIENT_EXISTS_FLAG,
               LPAD(TO_VARCHAR(v.CLIENTS_ID), 10, '0')  AS pkey_src_object,
               sts.DEACTIVATION_STS                     AS deactivation_sts,
               xref.HUB_STATE_IND                       AS hub_state_ind,
               fn_snow_helper15_common(v.FIRSTNAME, v.MIDDLENAME, v.LASTNAME,
                   TRIM(NVL(v.FIRSTNAME, '') || IFF(v.MIDDLENAME IS NOT NULL, ' ' || TRIM(v.MIDDLENAME), '')
                        || ' ' || NVL(LTRIM(v.LASTNAME), '')),
                   NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
          FROM V_TTF_ETL_SRC v
          LEFT JOIN sts  ON sts.SRC_KEY = LPAD(TO_VARCHAR(v.CLIENTS_ID), 10, '0')
          LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = LPAD(TO_VARCHAR(v.CLIENTS_ID), 10, '0')
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(v.FIRSTNAME)) AND jf.IS_FIRST_JUNK
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(v.LASTNAME)) AND jl.IS_LAST_JUNK
    )
    SELECT * FROM enriched;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_VAL_S1_ENRICHED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ENRICHED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_VAL_S1_ENRICHED', 'CREATED',
        'One row per TTF client, joined to its latest inactive status and cross-reference row, '
        || 'with standardised names attached. Read by the naming step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ENRICHED', :l_rows) || CHR(10);

    -- ---- Step 20: NAME FLAGS -- standardised names + validity flags -----
    -- Purpose: pull the standardised names out of the name object and
    -- flag each client as name-missing, name-declined or
    -- name-undisclosed.  These three flags drive every router group in
    -- step 30.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_VAL_S2_NAMED AS
    SELECT n.*,
           n.nm:first_name::VARCHAR    AS std_first_name,
           n.nm:middle_name::VARCHAR   AS std_mdl_name,
           n.nm:last_name::VARCHAR     AS std_lst_name,
           n.nm:src_full_name::VARCHAR AS std_src_full_name,
           /* VALIDATION */
           (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
            OR fn_snow_helper03_common(n.nm:last_name::VARCHAR))                          AS name_missing,
           NVL(UPPER(n.nm:last_name::VARCHAR) = 'DECLINED'
               OR UPPER(n.nm:first_name::VARCHAR) = 'DECLINED', FALSE)                    AS name_declined,
           NVL(UPPER(n.nm:last_name::VARCHAR) = 'DO_NOT_DISCLOSE'
               OR UPPER(n.nm:first_name::VARCHAR) = 'DO_NOT_DISCLOSE', FALSE)             AS name_undisclosed
      FROM WRK_TTF_VAL_S1_ENRICHED n;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_VAL_S2_NAMED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'NAMED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_VAL_S2_NAMED', 'CREATED',
        'Standardised first / middle / last names pulled out, with blank, DECLINED and DO_NOT_DISCLOSE flags. '
        || 'Read by the router step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 NAMED', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTER -- invalid name / deactivation / reactivation --
    -- Purpose: the publish-ready rows.  Each client is placed in its
    -- router groups (a client can be in more than one: an invalid name
    -- also deactivates, unless it is DO_NOT_DISCLOSE), given its
    -- exception code (missing vs invalid first vs last name), the new
    -- deactivation status derived from its hub state, and the
    -- first-row-per-exception-key flag (uq_exc_name) that keeps the
    -- exception table free of duplicates within the run.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TTF_VAL_S3_ROUTED AS
    WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
    routed AS (
        SELECT r.*,
               (r.name_missing OR r.name_declined OR r.name_undisclosed)                      AS grp_invalid_party_name,
               (r.name_missing OR r.name_declined OR NVL(r.CLIENT_EXISTS_FLAG = 'N', FALSE))  AS grp_deactivation,
               NVL(r.deactivation_sts IS NOT NULL AND NOT r.name_missing
                   AND NOT (UPPER(r.std_lst_name) = 'DECLINED') AND NOT (UPPER(r.std_first_name) = 'DECLINED')
                   AND r.CLIENT_EXISTS_FLAG = 'Y', FALSE)                                      AS grp_reactivation,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                    WHEN UPPER(TRIM(r.std_first_name)) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_First_Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name'
                    WHEN UPPER(TRIM(r.std_lst_name)) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_Last_Name'
                    ELSE 'Valid' END                                                           AS exc_code_name,
               fn_snow_helper02_common(r.hub_state_ind)                                        AS new_deactivation_sts
          FROM WRK_TTF_VAL_S2_NAMED r
    )
    SELECT r.*,
           ex.EXCEPTION_DESC     AS exc_desc_name,
           ex.EXCEPTION_TYPE     AS exc_type_name,
           'TTF'                 AS src_sys,
           :l_run_ts             AS run_ts,
           :c_mapping            AS mapping_name,
           'Deactivation'        AS action_deactivation,
           'Reactivation'        AS action_reactivation,
           /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
           ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.pkey_src_object, ex.EXCEPTION_TYPE,
                                           r.exc_code_name ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1 AS uq_exc_name
      FROM routed r
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TTF_VAL_S3_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TTF_VAL_S3_ROUTED', 'CREATED',
        'Router rows: invalid-name / deactivation / reactivation groups, exception code with description and type, '
        || 'and the first-row-per-exception-key flag (uq_exc_name). Published in step 40.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTED', :l_rows) || CHR(10);

    -- ---- Step 40: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-30 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning.  The four INSERTs below are the
    -- four branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHERE conditions -- only the
    -- source changed, from the final SELECT to step 30.
    BEGIN TRANSACTION;
    -- 40a. Write_Invalid_Party_Name -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, RUN_DATE,
            SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE, BIRTH_DATE, ATTRIBUTE_VALUE)
    SELECT CREATEDDATE, mapping_name, exc_code_name /* ATTRIBUTE_NAME_Name has the same expression */,
           std_first_name, std_mdl_name, std_lst_name, run_ts, src_sys, pkey_src_object, exc_desc_name,
           exc_type_name, exc_code_name, DOB, std_src_full_name
      FROM WRK_TTF_VAL_S3_ROUTED
     WHERE grp_invalid_party_name AND uq_exc_name;
    l_rows := SQLROWCOUNT;
    -- 40b. Write_STG_TTF_PTY_INACTIVE_LOG (Exp_Log_Deactv)
    INSERT INTO STG_TTF_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT pkey_src_object, src_sys, action_deactivation, run_ts
      FROM WRK_TTF_VAL_S3_ROUTED
     WHERE grp_deactivation;
    l_rows := :l_rows + SQLROWCOUNT;
    -- 40c. Filt_new_deactivations -> Write_STG_TTF_PTY_INACTIVE_STS2
    INSERT INTO STG_TTF_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT pkey_src_object, src_sys, new_deactivation_sts, run_ts
      FROM WRK_TTF_VAL_S3_ROUTED
     WHERE grp_deactivation AND deactivation_sts IS NULL;
    l_rows := :l_rows + SQLROWCOUNT;
    -- 40d. Write_STG_TTF_PTY_INACTIVE_LOG1 (Exp_Log_Reactv)
    INSERT INTO STG_TTF_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT pkey_src_object, src_sys, action_reactivation, run_ts
      FROM WRK_TTF_VAL_S3_ROUTED
     WHERE grp_reactivation;
    l_rows := :l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PUBLISH', 'COMPLETED',
        'EXC_STG_BAD_REC_MEMB, STG_TTF_PTY_INACTIVE_LOG, STG_TTF_PTY_INACTIVE_STS',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: invalid-name exceptions, deactivation log rows, new deactivation '
        || 'status rows, and reactivation log rows. Count shown is total rows inserted across all four inserts.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PUBLISH (total inserted)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TTF_Pty_Validation completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TTF_Pty_Validation failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
