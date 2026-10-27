-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, workflow
-- wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-35  Authorised-representative attributes load SECOND, into the
--          same C_S_TRS_PTY_MNG_ATTR table as the switch attributes,
--          without wiping them.  Runs AFTER
--          m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw, never in parallel with it.
--   BR-10  Only valid members (STG_TRS_VALID_MEMBERS spine) get attributes.
--   BR-01  Insert-only staging load (see Parity notes: no truncate and,
--          in this Snowflake version, no delete either).
--   The flag itself: 'Auth_Rep_Flag' = 'Y' for members whose case has a
--   verified, sent authorised representative -- verification codes
--   CS / FH / LD / OA and SENT_AUTHREP_SW = 'Y'.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (a -> src -> keyed ->
--   agg -> final SELECT with the existing-key guard), one transaction,
--   one log line.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original final SELECT, written as a
--   single INSERT inside ONE transaction (it was the only INSERT in the
--   original, so there is nothing to split into INSERT ALL branches).
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_MNGAR_S10_PAYEE  payee/case/EDG rows with a verified,
--                                     sent authorised representative (6 branches)
--   Step 20  WRK_TRS_MNGAR_S20_SRC    valid members only (spine join)
--   Step 30  WRK_TRS_MNGAR_S30_KEYED  distinct rows, key = INDV_ID|Auth_Rep_Flag
--   Step 40  WRK_TRS_MNGAR_S40_AGG    one row per key: last row + MAX end date
--   Step 50  PUBLISH                  C_S_TRS_PTY_MNG_ATTR, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_MNGAR_S10_PAYEE, WRK_TRS_MNGAR_S20_SRC, WRK_TRS_MNGAR_S30_KEYED,
--   WRK_TRS_MNGAR_S40_AGG.  They live in the same schema as the target
--   (unqualified names, as in the original code), are prefixed WRK_TRS_,
--   and are registered in JOB_CONTROL_ETL at creation.
--   They survive a session crash (TRANSIENT, not TEMP), which is what
--   makes inspection after a run possible; a pure session TEMP table would vanish with
--   the session.  A Snowflake CURSOR
--   was NOT used: cursors process row by row, and every step here is
--   set-based by design -- the work table IS the result set, held as a
--   table instead of in memory, so it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * IDQ deletes ONLY its own attribute type from C_S_TRS_PTY_MNG_ATTR
--     before loading (pre-SQL: DELETE ... WHERE MNG_ATTR_TP =
--     '$ATTR_TP_AUTH_REP').  THE SNOWFLAKE ORIGINAL DOES NOT DO THIS:
--     it contains no DELETE at all, and this rewrite preserves that --
--     it only skips keys already present in the target (VERSION_SEQ = 1)
--     and keeps one row per key in this run.  Consequence, stated
--     plainly: a re-run inserts nothing twice, but a stale
--     Auth_Rep_Flag row that IDQ would have deleted and reloaded is
--     left in place by this version.  If IDQ parity is required, the
--     delete must be added as an explicit publish sub-step inside the
--     step-50 transaction (see the User Guide, "Parity gaps") -- it has
--     NOT been invented here.
--   * Insert-only otherwise, as in the original Snowflake code: no
--     TRUNCATE of the target.  IDQ truncates nothing for this mapping
--     either (it appends); the difference is only the delete above.
--   * VERSION_SEQ is hard-coded to 1; PERIOD_START_DATE = EFF_BEGIN_DT
--     of the last row, PERIOD_END_DATE = MAX(EFF_END_DT) per key.
--     Last row per key = latest EFF_BEGIN_DT (NULL high), as in the
--     original, which assumes the key-only distinct re-sort keeps it.
--
-- SIGNATURE
--   The original parameter is unchanged and in the same order, so every
--   existing CALL still works.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (
    P_ATTR_TP_AUTH_REP VARCHAR DEFAULT 'Auth_Rep_Flag',
    P_JOB_RUN_ID       VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing';
    l_run_ts     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    l_job_run_id VARCHAR;
    l_rows       NUMBER DEFAULT 0;
    l_pub_rows   NUMBER DEFAULT 0;
    l_summary    VARCHAR DEFAULT '';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(:P_JOB_RUN_ID, ''),
            'TRS_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_TRS_MNGAR_S10_PAYEE;
    DROP TABLE IF EXISTS WRK_TRS_MNGAR_S20_SRC;
    DROP TABLE IF EXISTS WRK_TRS_MNGAR_S30_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_MNGAR_S40_AGG;

    -- ---- Step 10: PAYEE / CASE / EDG ROWS (BR-35) ------------------------
    -- Purpose: every individual whose case has a verified, sent
    -- authorised representative, from six union branches over the
    -- payee, case and EDG delta tables (In1, In2, In3, Out1, Inner,
    -- Out3 in the original).  Branch conditions are verbatim: mailing
    -- address type ('MA' or null), ALT_PAYEE_EXISTS_SW = 'Y', open
    -- eligibility (elig_eff_end_dt IS NULL where the branch requires
    -- it), verification code in CS/FH/LD/OA, SENT_AUTHREP_SW = 'Y'.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGAR_S10_PAYEE AS
    SELECT ed.indv_id, 'Y' AS AR_FLAG, ed.elig_eff_begin_dt AS eff_begin_dt, ed.elig_eff_end_dt AS eff_end_dt,
           p.create_dt AS create_dt
      FROM STG_TRS_D_DC_PRIMARY_PAYEE p
      JOIN STG_TRS_CV_ED_MCI_EDG_INDV ed
        ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
      JOIN STG_TRS_DC_CASES c ON p.case_num = c.case_num
     WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
      FROM STG_TRS_D_DC_CASES c
      JOIN STG_TRS_DC_PRIMARY_PAYEE p ON p.case_num = c.case_num
      JOIN STG_TRS_CV_ED_MCI_EDG_INDV ed
        ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
     WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
      FROM STG_TRS_DC_CASES c
      JOIN STG_TRS_DC_PRIMARY_PAYEE p ON p.case_num = c.case_num
      JOIN STG_TRS_D_CV_ED_MCI_EDG_INDV ed
        ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
     WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt)
      FROM STG_TRS_D_CV_ED_MCI_EDG_INDV ed
      LEFT JOIN STG_TRS_DC_PRIMARY_PAYEE p
        ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
       AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND p.edg_num IS NULL
      JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
      JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
     WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
      FROM STG_TRS_CV_ED_MCI_EDG_INDV ed
      JOIN STG_TRS_D_DC_PRIMARY_PAYEE p
        ON ed.case_num = ed.case_num AND ed.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
       AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND p.edg_num IS NULL
      JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
      JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
     WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt)
      FROM STG_TRS_CV_ED_MCI_EDG_INDV ed
      LEFT JOIN STG_TRS_DC_PRIMARY_PAYEE p
        ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
       AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND p.edg_num IS NULL
      JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
      JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
     WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y';
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGAR_S10_PAYEE;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'PAYEE_CASE_ROWS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGAR_S10_PAYEE', 'CREATED',
        'Payee/case/EDG rows with a verified, sent authorised representative (six branches). '
        || 'Read by the valid-member step (BR-35).',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 PAYEE_CASE_ROWS', :l_rows) || CHR(10);

    -- ---- Step 20: VALID MEMBERS ONLY (BR-10) -----------------------------
    -- Purpose: distinct rows for individuals on the valid-member spine
    -- (matched on TO_VARCHAR(INDV_ID) = PTY_PK).  Every later step reads
    -- this table, never step 10 again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGAR_S20_SRC AS
    SELECT DISTINCT a.indv_id AS INDV_ID, a.AR_FLAG, a.eff_begin_dt AS EFF_BEGIN_DT, a.eff_end_dt AS EFF_END_DT,
           a.create_dt AS CREATE_DT
      FROM WRK_TRS_MNGAR_S10_PAYEE a
      JOIN STG_TRS_VALID_MEMBERS IM ON TO_VARCHAR(a.INDV_ID) = IM.PTY_PK;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGAR_S20_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'VALID_SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGAR_S20_SRC', 'CREATED',
        'Distinct authorised-representative rows for valid members only. '
        || 'Read by the keying step; never re-read step 10 after this point.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 VALID_SRC', :l_rows) || CHR(10);

    -- ---- Step 30: KEYING (BR-35) ------------------------------------------
    -- Purpose: distinct rows with the staging key
    -- INDV_ID || '|' || P_ATTR_TP_AUTH_REP (default 'Auth_Rep_Flag')
    -- and the party foreign key (the individual id as text).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGAR_S30_KEYED AS
    SELECT DISTINCT s.INDV_ID, s.AR_FLAG, s.EFF_BEGIN_DT, s.EFF_END_DT, s.CREATE_DT,
           TO_VARCHAR(s.INDV_ID) || '|' || :P_ATTR_TP_AUTH_REP AS pkey_src_object,
           TO_VARCHAR(s.INDV_ID) AS pty_pk
      FROM WRK_TRS_MNGAR_S20_SRC s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGAR_S30_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGAR_S30_KEYED', 'CREATED',
        'Distinct rows keyed INDV_ID|Auth_Rep_Flag. Read by the aggregation step (BR-35).',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 KEYED', :l_rows) || CHR(10);

    -- ---- Step 40: AGGREGATE -- one row per key -----------------------------
    -- Purpose: one row per staging key: every port from the last row of
    -- the group (latest EFF_BEGIN_DT, NULL high, then EFF_END_DT, then
    -- CREATE_DT) and PERIOD_END_DATE = MAX(EFF_END_DT) for the key.
    -- This is the exact input to the publish step; the existing-key
    -- guard stays in the publish SELECT, as in the original, because
    -- it reads the live target at publish time.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_MNGAR_S40_AGG AS
    SELECT k.*,
           MAX(k.EFF_END_DT) OVER (PARTITION BY k.pkey_src_object) AS max_eff_end_dt,
           ROW_NUMBER() OVER (PARTITION BY k.pkey_src_object
                              ORDER BY k.EFF_BEGIN_DT DESC NULLS FIRST, k.EFF_END_DT DESC NULLS FIRST,
                                       k.CREATE_DT DESC NULLS FIRST) AS rn
      FROM WRK_TRS_MNGAR_S30_KEYED k;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_MNGAR_S40_AGG;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'AGG_DEDUP', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_MNGAR_S40_AGG', 'CREATED',
        'One row per key (rn = 1 is the row that loads), with MAX end date per key. '
        || 'Read by the publish step (BR-35).',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 AGG', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction -----------------------------
    -- This is the ONLY step that writes to a final target, and it writes
    -- NOTHING else: in particular it does NOT delete the mapping's own
    -- attribute type from C_S_TRS_PTY_MNG_ATTR, although IDQ does (see
    -- Parity notes).  The INSERT below is the original final SELECT
    -- verbatim, with its FROM pointed at step 40: last row per key
    -- (rn = 1) whose key is not already in the target (VERSION_SEQ = 1).
    BEGIN TRANSACTION;
    INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (CREATE_DATE, LAST_UPDATE_DATE, MNG_ATTR_TP, PTY_FK, PERIOD_END_DATE, PERIOD_START_DATE, VERSION_SEQ,
            SRC_ROWID, PKEY_SRC_OBJECT, SRC_LAST_UPD_DT, MNG_ATTR_VAL)
    SELECT g.CREATE_DT, :l_run_ts, :P_ATTR_TP_AUTH_REP, g.pty_pk, g.max_eff_end_dt,
           g.EFF_BEGIN_DT, 1, g.pkey_src_object,
           g.pkey_src_object, g.CREATE_DT, g.AR_FLAG
      FROM WRK_TRS_MNGAR_S40_AGG g
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_MNG_ATTR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = g.pkey_src_object
     WHERE g.rn = 1
       AND xa.PKEY_SRC_OBJECT IS NULL;
    l_pub_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED', 'C_S_TRS_PTY_MNG_ATTR', :l_pub_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: authorised-representative flags for valid members. '
        || 'Count shown is rows inserted into C_S_TRS_PTY_MNG_ATTR. '
        || 'No delete of the mapping''s own attribute type was performed (see Parity notes).');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (C_S_TRS_PTY_MNG_ATTR)', :l_pub_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
