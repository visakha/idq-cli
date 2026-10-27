-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Validation, workflow wf_ECI_Stage_Load
-- (first step of the workflow). Install schema is ECI_ETL_WRK in
-- database MDM_ETL_ECI; all table names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Checks every ECI child and family party of the delta and maintains
--   the deactivation list that every later ECI mapping uses as a filter:
--   parties whose standardised first or last name is blank are written
--   to the exception table and to the deactivation log; parties that
--   are blank-named, duplicate cases, or from an inactive family are
--   deactivated (log row, plus a status row only when the party has no
--   status yet); parties that already have a status, have names
--   present, are not duplicates and are from an active family are
--   reactivated (log row). A row goes to every group whose condition is
--   true, so blank-name rows are also deactivation rows.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src ->
--   exp_load -> sts / xref / dup / fam -> enriched -> named -> routed
--   -> final SELECT), one transaction, one log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_VAL_S10_SRC      child + family delta rows, party
--                                     key and 10-character full name
--   Step 20  WRK_ECI_VAL_S20_ENRICHED status / hub / duplicate / family
--                                     lookups + standardised names
--   Step 30  WRK_ECI_VAL_S30_ROUTED   exception groups (blank name,
--                                     deactivation, reactivation) with
--                                     exception descriptions and the
--                                     first-row-per-exception-key flag
--   Step 40  PUBLISH                targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_VAL_S10_SRC, WRK_ECI_VAL_S20_ENRICHED,
--   WRK_ECI_VAL_S30_ROUTED. They live in the same schema as the targets
--   (unqualified names, as in the original code) and are prefixed
--   WRK_ECI_. They survive a session crash (TRANSIENT, not TEMP), which
--   is what makes inspection after a run possible. No CURSOR was used:
--   every step here is set-based by design -- the work table IS the
--   result set, held as a table instead of in memory, so it can be
--   counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ delete of STG_ECI_PTY_INACTIVE_STS
--     (Upd_Delete_Inactive) is NOT performed, exactly as in the
--     original.
--   * The full name passed to name standardisation is cut at 10
--     characters (the IDQ port is declared string(10)); preserved.
--   * No prefix / suffix is passed to name standardisation, so their
--     lookups cannot match; preserved.
--   * The exception row takes its description and type from
--     EXC_LOOKUP_CODE_VALUE (NULL when the code is not configured);
--     preserved. A second row with the same exception key in this run
--     is not written (uq_exc_name flag).
--   * The hub cross-reference lookup trims ROWID_SYSTEM to 'ECI'
--     (the MDM column is blank-padded); preserved.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
    l_run_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_pub_rows   NUMBER DEFAULT 0;
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
    DROP TABLE IF EXISTS WRK_ECI_VAL_S10_SRC;
    DROP TABLE IF EXISTS WRK_ECI_VAL_S20_ENRICHED;
    DROP TABLE IF EXISTS WRK_ECI_VAL_S30_ROUTED;

    -- ---- Step 10: CHILD + FAMILY DELTA ROWS ------------------------------
    -- Purpose: the delta parties (child rows plus family rows), each
    -- with its party key (zero-padded id, plus 'F' for family rows)
    -- and the 10-character full name fed to name standardisation.
    -- This is the original src + Exp_ECI_Data_Load CTEs.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_VAL_S10_SRC AS
    WITH
    src AS (
        SELECT 'ECI_CHILD' AS SOURCE_TABLE, c.ID_CHILD AS ID, c.FIRST_NAME, c.LAST_NAME, c.MIDDLE_INITIAL,
               c.DOB, c.DATE_CREATED, c.DATE_MODIFIED, c.MODIFIED_BY, c.CREATED_BY, c.LOAD_DATE
          FROM STG_ECI_D_CHILD c
        UNION ALL
        SELECT 'ECI_FAMILY' AS SOURCE_TABLE, fam.ID_FAMILY AS ID, fam.FIRST_NAME, fam.LAST_NAME,
               fam.MIDDLE_INITIAL, fam.DOB, fam.DATE_CREATED, fam.DATE_MODIFIED, fam.MODIFIED_BY,
               fam.CREATED_BY, fam.LOAD_DATE
          FROM STG_ECI_D_FAMILY fam
    )
    SELECT s.*,
           LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')   AS pkey_src_object,
           'ECI'                                                                           AS src_system,
           SUBSTR(TRIM(NVL(s.FIRST_NAME, '')
                       || IFF(s.MIDDLE_INITIAL IS NOT NULL, ' ' || TRIM(s.MIDDLE_INITIAL), '')
                       || ' ' || NVL(LTRIM(s.LAST_NAME), '')), 1, 10)                       AS full_name
      FROM src s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_VAL_S10_SRC;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_DELTA_PARTIES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_VAL_S10_SRC', 'CREATED',
        'Child and family delta parties with party keys and the 10-character full name. '
        || 'Read by the enrichment step; the delta tables are not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_DELTA_PARTIES', :l_rows) || CHR(10);

    -- ---- Step 20: LOOKUPS + NAME STANDARDISATION ------------------------
    -- Purpose: join each party to its current deactivation status, its
    -- hub cross-reference state, the duplicate-case list and the family
    -- validation list, and standardise its names. Reads ONLY step 10
    -- (plus the reference lookups). This is the original sts / xref /
    -- dup / fam CTEs plus the enriched CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_VAL_S20_ENRICHED AS
    WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (
        SELECT i.SRC_KEY, i.ROWID_SYSTEM, i.DEACTIVATION_STS
          FROM STG_ECI_PTY_INACTIVE_STS i
       QUALIFY ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY, i.ROWID_SYSTEM
                                      ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) = 1
    ),
    xref AS (
        SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'ECI'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) = 1
    ),
    dup AS (
        SELECT DISTINCT d.SOURCE_TABLE, d.ID FROM V_ECI_ETL_LU_DUP_CASES d
    ),
    fam AS (
        SELECT f.SOURCE_TABLE, f.ID_FAMILY, f.FAM_NAME_STATUS, f.FAM_PHONE_AND_ADDRESS_STS, f.FAM_INACTIVE_STS
          FROM V_ECI_ETL_LU_FAMILY_VALIDATION f
       QUALIFY ROW_NUMBER() OVER (PARTITION BY f.SOURCE_TABLE, f.ID_FAMILY ORDER BY f.ID_FAMILY) = 1
    )
    SELECT e.*,
           sts.DEACTIVATION_STS                                                    AS deactivation_sts,
           xref.HUB_STATE_IND                                                      AS hub_state_ind,
           dup.ID                                                                  AS omit_id,
           IFF(fam.FAM_NAME_STATUS IS NULL AND fam.FAM_PHONE_AND_ADDRESS_STS IS NULL
               AND fam.FAM_INACTIVE_STS IS NULL, 'N', 'Y')                         AS fam_inactive_yn,
           fn_snow_helper15_common(e.FIRST_NAME, e.MIDDLE_INITIAL, e.LAST_NAME, e.full_name, NULL, NULL,
                                   NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
      FROM WRK_ECI_VAL_S10_SRC e
      LEFT JOIN sts  ON sts.SRC_KEY = e.pkey_src_object AND sts.ROWID_SYSTEM = e.src_system
      LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = e.pkey_src_object
      LEFT JOIN dup  ON dup.SOURCE_TABLE = e.SOURCE_TABLE AND dup.ID = e.ID
      LEFT JOIN fam  ON fam.SOURCE_TABLE = e.SOURCE_TABLE AND fam.ID_FAMILY = e.ID
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(e.FIRST_NAME)) AND jf.IS_FIRST_JUNK
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(e.LAST_NAME)) AND jl.IS_LAST_JUNK;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_VAL_S20_ENRICHED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'ENRICHED_STD_NAMES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_VAL_S20_ENRICHED', 'CREATED',
        'Parties joined to deactivation status, hub state, duplicate cases and family validation, '
        || 'with standardised names. Read by the routing step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 ENRICHED_STD_NAMES', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTING -- exception / deactivation / reactivation ----
    -- Purpose: the routing decisions. A row can belong to more than one
    -- group: blank-name rows are both exception rows and deactivation
    -- rows. Missing first name wins over missing last name. Reads ONLY
    -- step 20. This is the original named + routed CTEs plus the final
    -- SELECT (exception description/type lookup, run timestamp, action
    -- labels, first-row-per-exception-key flag).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_VAL_S30_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    named AS (
        SELECT n.*,
               n.nm:first_name::VARCHAR  AS std_first_name,
               n.nm:middle_name::VARCHAR AS std_mdl_name,
               n.nm:last_name::VARCHAR   AS std_lst_name,
               (fn_snow_helper03_common(n.nm:first_name::VARCHAR)
                OR fn_snow_helper03_common(n.nm:last_name::VARCHAR)) AS name_missing
          FROM WRK_ECI_VAL_S20_ENRICHED n
    ),
    routed AS (
        SELECT r.*,
               (r.name_missing AND r.fam_inactive_yn = 'N')                                  AS grp_invalid_party_name,
               (r.name_missing OR r.omit_id IS NOT NULL OR r.fam_inactive_yn = 'Y')          AS grp_deactivation,
               (r.deactivation_sts IS NOT NULL AND NOT r.name_missing AND r.omit_id IS NULL
                AND r.fam_inactive_yn = 'N')                                                 AS grp_reactivation,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'Missing_First_Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Missing_Last_Name' END AS exc_code_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN 'First Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN 'Last Name' END        AS exc_attribute_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) THEN r.std_first_name
                    WHEN fn_snow_helper03_common(r.std_lst_name) THEN r.std_lst_name END     AS exc_attribute_value,
               fn_snow_helper02_common(r.hub_state_ind)                                      AS new_deactivation_sts
          FROM named r
    )
    SELECT r.*,
           ex.EXCEPTION_DESC     AS exc_desc_name,
           ex.EXCEPTION_TYPE     AS exc_type_name,
           :l_run_ts             AS run_ts,
           :c_mapping            AS mapping_name,
           'Deactivation'        AS action_deactivation,
           'Reactivation'        AS action_reactivation,
           ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.src_system, r.pkey_src_object,
                                           ex.EXCEPTION_TYPE, r.exc_code_name
                                  ORDER BY r.ID) = 1 AS uq_exc_name
      FROM routed r
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_VAL_S30_ROUTED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTED_GROUPS', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB, STG_ECI_PTY_INACTIVE_LOG, STG_ECI_PTY_INACTIVE_STS', :l_rows, NULL,
        'WRK_ECI_VAL_S30_ROUTED', 'CREATED',
        'Routed parties: blank-name exception candidates, deactivation candidates and reactivation '
        || 'candidates, with exception descriptions resolved and the first-row-per-key flag (uq_exc_name). '
        || 'Published in step 40.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTED_GROUPS', :l_rows) || CHR(10);

    -- ---- Step 40: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The four INSERTs below are
    -- the four branches of the original INSERT ALL, in the same order,
    -- with the same column lists, values and WHERE conditions -- only
    -- the source changed, from the final SELECT to step 30. No
    -- TRUNCATE, no DELETE: the IDQ delete of the inactive-status table
    -- is not performed, as in the original.
    BEGIN TRANSACTION;
    -- 40a. Invalid party name -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
            PERIOD_START_DATE)
    SELECT src_system, pkey_src_object, exc_code_name, exc_desc_name, exc_type_name, run_ts,
           std_first_name, std_mdl_name, std_lst_name, DOB, exc_attribute_name, exc_attribute_value,
           mapping_name, DATE_CREATED
      FROM WRK_ECI_VAL_S30_ROUTED
     WHERE grp_invalid_party_name AND uq_exc_name;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 40b. Deactivation -> STG_ECI_PTY_INACTIVE_LOG
    INSERT INTO STG_ECI_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT pkey_src_object, src_system, action_deactivation, run_ts
      FROM WRK_ECI_VAL_S30_ROUTED
     WHERE grp_deactivation;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 40c. New deactivations (no status yet) -> STG_ECI_PTY_INACTIVE_STS
    INSERT INTO STG_ECI_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT pkey_src_object, src_system, new_deactivation_sts, run_ts
      FROM WRK_ECI_VAL_S30_ROUTED
     WHERE grp_deactivation AND deactivation_sts IS NULL;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 40d. Reactivation -> STG_ECI_PTY_INACTIVE_LOG
    INSERT INTO STG_ECI_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
    SELECT pkey_src_object, src_system, action_reactivation, run_ts
      FROM WRK_ECI_VAL_S30_ROUTED
     WHERE grp_reactivation;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    l_rows := l_pub_rows;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PUBLISH', 'COMPLETED',
        'EXC_STG_BAD_REC_MEMB, STG_ECI_PTY_INACTIVE_LOG, STG_ECI_PTY_INACTIVE_STS',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: blank-name exceptions, deactivation log and status rows, '
        || 'and reactivation log rows. Count shown is rows inserted across all publish branches.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_ECI_Pty_Validation completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_ECI_Pty_Validation failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
