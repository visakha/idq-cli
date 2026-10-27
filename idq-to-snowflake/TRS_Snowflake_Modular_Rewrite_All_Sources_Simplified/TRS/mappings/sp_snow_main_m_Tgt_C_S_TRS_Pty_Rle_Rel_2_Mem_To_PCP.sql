-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP, workflow
-- wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-37  Member-to-PCP relationships are provider-number driven, and
--          only against the C21 source of TPIs: the provider number
--          must be numeric and known as a C21 TPI alternate ID ('006')
--          in the MDM; the type is 'Member PCO' when the provider key
--          holds '|HCO', otherwise 'Member PCP'; the relationship key
--          is member | provider | 100 (P_PCP_REL_TP).
--   BR-38  Relationship timelines are validated, not assumed: start
--          <= end (null end date = open), DST-corrected end dates,
--          end-dated rows emitted twice (closed + open copy),
--          VERSION_SEQ re-numbered per key.
--   BR-02  A missing member or provider key, or a reversed period, is
--          logged, not loaded; a non-numeric provider number is
--          dropped silently by the numeric filter.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (min_pk -> src ->
--   tpi_src_key -> keyed -> routed -> consolidated -> prepared ->
--   versions -> ranked -> timeline_flagged, plus router ->
--   router_flagged, unioned into both_kinds with a final SELECT), one
--   transaction, one log line at the end.  If it failed, nothing told
--   you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The original both_kinds UNION is NOT recreated as a work
--   table: the router branch (step 30) and the timeline branch
--   (steps 40-60) stay separate, and the publish step reads each one
--   directly, with the original WHEN conditions as WHERE clauses (the
--   final SELECT's exception descriptions/types and label constants
--   are resolved in the router step, so the publish INSERTs are plain
--   column-to-column copies).  The final publish is the original
--   INSERT ALL branches, written as separate INSERT statements (one
--   per target) inside ONE transaction, so a publish either lands
--   completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_REL2_S1_SRC       managed-care rows with a numeric
--                                      provider number, member joined
--                                      to the valid-member spine
--   Step 20  WRK_TRS_REL2_S2_KEYED     provider resolved to its C21 TPI
--                                      key, member/provider keys built,
--                                      relationship key + validity +
--                                      dates-reversed flags
--   Step 30  WRK_TRS_REL2_S3_ROUTER    exception code (Invalid_Member /
--                                      Invalid_PCP), first-row flags +
--                                      exception descriptions/types
--            (branch: step 30 reads step 20 -- the exception branch)
--   Step 40  WRK_TRS_REL2_S4_CONSOL    valid rows only, one row per
--                                      (key, end date, start date)
--            (branch: step 40 reads step 20, NOT step 30 -- valid and
--             exception rows are two branches of the same keyed output)
--   Step 50  WRK_TRS_REL2_S5_PREP      DST-corrected end date
--   Step 60  WRK_TRS_REL2_S6_TIMELINE  timeline versions (closed +
--                                      open copy), re-numbered,
--                                      timeline action / hub state /
--                                      insert-only guard set
--   Step 70  PUBLISH                   targets, in one transaction
--                                      (reads steps 30 and 60)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_REL2_S1_SRC, WRK_TRS_REL2_S2_KEYED, WRK_TRS_REL2_S3_ROUTER,
--   WRK_TRS_REL2_S4_CONSOL, WRK_TRS_REL2_S5_PREP, WRK_TRS_REL2_S6_TIMELINE.
--   They live in the same schema as the targets (unqualified names, as
--   in the original code), are prefixed WRK_TRS_, and are registered in
--   JOB_CONTROL_ETL at creation.  They survive a
--   session crash (TRANSIENT, not TEMP), unlike a pure session TEMP
--   table, which would vanish with the session.  A Snowflake CURSOR was NOT used:
--   cursors process row by row, and every step here is set-based by
--   design -- the work table IS the result set, held as a table instead
--   of in memory, so it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_REL_PROV; the
--     Snowflake version instead skips keys already present (uq_rel).
--     A re-run therefore inserts nothing twice, but it also does not
--     remove rows that IDQ would have truncated away.
--   * A non-numeric provider number is dropped silently by
--     Filt_Numeric_Prov (fn_snow_helper01_common = 1) -- no exception
--     row is written for it, as in the original.
--   * The stored source filter PROVIDER_NUM is not null duplicates the
--     custom query's WHERE clause; both are preserved.
--   * The MDM cross-reference filter ROWID_SYSTEM = 'C21' is trimmed
--     (the MDM column is blank-padded), and only hub_state_ind = 1
--     rows are considered, with the latest source key per TPI kept.
--   * The provider key is the source key up to its second '|': if the
--     TPI lookup finds no row, the provider key is NULL (SUBSTR over
--     a NULL key), which is what makes the row an Invalid_PCP
--     exception -- preserved, not guarded with a COALESCE.
--   * Unfed ports written as NULL: CREATE_DATE (not fed into the
--     timeline mapplet in this mapping), ROWID_OBJECT, DELETED_*,
--     UPDATED_BY, CREATOR.  SRC_LAST_UPD_DT is the source CREATE_DT.
--     HUB_STATE_IND is 1 only on the open row with VERSION_SEQ 1;
--     PERIOD_REFERENCE_TIME is the (DST-corrected) end date and
--     TIMELINE_ACTION is 2 when end-dated, NULL when open.
--   * The timeline changes the ROW SET, not only column values:
--     every end-dated row is emitted twice (the closed version and an
--     open copy with the end date removed).  That duplication is the
--     original behaviour, preserved in step 60.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so
--   every existing CALL still works.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP (
    P_PCP_REL_TP VARCHAR DEFAULT '100',  -- $PCP_REL_TP
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP';
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
    DROP TABLE IF EXISTS WRK_TRS_REL2_S1_SRC;
    DROP TABLE IF EXISTS WRK_TRS_REL2_S2_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_REL2_S3_ROUTER;
    DROP TABLE IF EXISTS WRK_TRS_REL2_S4_CONSOL;
    DROP TABLE IF EXISTS WRK_TRS_REL2_S5_PREP;
    DROP TABLE IF EXISTS WRK_TRS_REL2_S6_TIMELINE;

    -- ---- Step 10: SOURCE -- numeric provider, member valid (BR-37) ------
    -- Purpose: managed-care rows that have a provider number, where
    -- the provider number is numeric (non-numeric rows are dropped
    -- silently here, with no exception) and the member is on the
    -- valid-member spine (one key per individual).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL2_S1_SRC AS
    WITH
    min_pk AS (
        SELECT indv_id, MIN(pty_pk) pty_pk FROM STG_TRS_VALID_MEMBERS GROUP BY indv_id
    )
    SELECT mc.indv_id AS INDV_ID, mc.history_seq AS HISTORY_SEQ, mc.mc_prog_code AS MC_PROG_CODE,
           mc.begin_dt AS BEGIN_DT, mc.create_dt AS CREATE_DT, mc.provider_num AS PROVIDER_NUM,
           mc.end_dt AS END_DT, vm.pty_pk AS PTY_PK
      FROM STG_TRS_D_IN_MANAGED_CARE mc
      JOIN min_pk vm ON mc.indv_id = vm.indv_id
     WHERE mc.provider_num IS NOT NULL
       AND fn_snow_helper01_common(mc.provider_num) = 1;  -- Filt_Numeric_Prov
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL2_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_MANAGED_CARE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL2_S1_SRC', 'CREATED',
        'Managed-care rows with a numeric provider number, member joined to the valid-member spine (BR-37). '
        || 'Read by the keying step; never re-read the raw sources after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_MANAGED_CARE', :l_rows) || CHR(10);

    -- ---- Step 20: KEYING -- resolve provider, build keys (BR-37) ---------
    -- Purpose: resolve the provider number to its C21 TPI source key
    -- (latest source key per TPI, hub_state_ind = 1), take the provider
    -- key up to its second '|', decide 'Member PCO' vs 'Member PCP',
    -- build the member key and the relationship key
    -- (member | provider | P_PCP_REL_TP), and flag validity (both keys
    -- present, start <= end or open) and reversed periods.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL2_S2_KEYED AS
    WITH
    tpi_src_key AS (
        SELECT bo.alt_id_val, xr.pkey_src_object
          FROM C_B_PTY_RLE_ALT_ID bo
         INNER JOIN C_B_PTY_RLE_ALT_ID_XREF xr ON bo.rowid_object = xr.rowid_object
         WHERE bo.alt_id_tp = '006' AND TRIM(xr.rowid_system) = 'C21' AND xr.hub_state_ind = 1
       QUALIFY ROW_NUMBER() OVER (PARTITION BY bo.alt_id_val ORDER BY xr.src_last_upd_dt DESC) = 1
    ),
    keyed AS (
        SELECT s.*,
               IFF(s.PTY_PK IS NULL, NULL, TRIM(s.PTY_PK) || '|Member')                        AS pty_rle_fk_1,
               SUBSTR(TRIM(t.pkey_src_object), 1, REGEXP_INSTR(TRIM(t.pkey_src_object), '[|]', 1, 2) - 1)
                                                                                              AS pty_rle_fk_2,
               IFF(CONTAINS(TRIM(t.pkey_src_object), '|HCO'), 'Member PCO', 'Member PCP')     AS rel_type_code
          FROM WRK_TRS_REL2_S1_SRC s
          LEFT JOIN tpi_src_key t ON t.alt_id_val = s.PROVIDER_NUM
    )
    SELECT k.*,
           NVL(k.pty_rle_fk_1, '') || '|' || NVL(k.pty_rle_fk_2, '') || '|' || :P_PCP_REL_TP AS pkey_src_object,
           /* VALIDATION */ NVL(k.BEGIN_DT > k.END_DT, FALSE)                              AS dates_reversed,
           /* VALIDATION */ (k.pty_rle_fk_1 IS NOT NULL AND k.pty_rle_fk_2 IS NOT NULL
                             AND NVL(k.BEGIN_DT <= k.END_DT OR k.END_DT IS NULL, FALSE))   AS is_valid
      FROM keyed k;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL2_S2_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL2_S2_KEYED', 'CREATED',
        'Rows with C21 provider key resolved, member/provider keys, relationship key, validity and reversed-period flags (BR-37). '
        || 'Read by both the router step and the consolidation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 KEYED', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTER -- exception code, flags, descriptions ---------
    -- Purpose: the exception branch.  Decide the default exception
    -- code (Invalid_Member when the member key is missing, Invalid_PCP
    -- when the provider key is missing), set the first-row-per-
    -- exception-key flags, and resolve the exception descriptions/
    -- types and label constants exactly as the original final SELECT
    -- did, so the publish step can copy them straight into
    -- EXC_STG_BAD_REC_MEMB.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL2_S3_ROUTER AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    router AS (
        SELECT r.*,
               CASE WHEN r.pty_rle_fk_1 IS NULL THEN 'Invalid_Member'
                    WHEN r.pty_rle_fk_2 IS NULL THEN 'Invalid_PCP' END                 AS exc_default_code
          FROM WRK_TRS_REL2_S2_KEYED r
    ),
    router_flagged AS (
        SELECT r.*,
               /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.dates_reversed, r.INDV_ID, r.PROVIDER_NUM, r.pty_rle_fk_2
                                      ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_dates,
               ROW_NUMBER() OVER (PARTITION BY NOT r.is_valid AND NOT r.dates_reversed, r.INDV_ID,
                                               r.PROVIDER_NUM, r.exc_default_code
                                      ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_default
          FROM router r
    )
    SELECT r.*,
           'Member'                                      AS hierarchy_code,
           'Effective Date'                              AS attr_dates,
           'Provider'                                    AS attr_provider,
           'Period_Start_Date_>_Period_End_Date'         AS exc_dates_code,
           xd.EXCEPTION_DESC                             AS exc_dates_desc,
           xd.EXCEPTION_TYPE                             AS exc_dates_type,
           xx.EXCEPTION_DESC                             AS exc_default_desc,
           xx.EXCEPTION_TYPE                             AS exc_default_type
      FROM router_flagged r
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date'
      LEFT JOIN lkp_exc xx ON xx.EXCEPTION_CODE = r.exc_default_code;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL2_S3_ROUTER;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTER_EXCEPTIONS', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_TRS_REL2_S3_ROUTER', 'CREATED',
        'Router rows: default exception code, first-row flags and descriptions/types resolved (BR-02). '
        || 'Read by the exception publish branches only.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTER', :l_rows) || CHR(10);

    -- ---- Step 40: CONSOLIDATION -- valid rows only (BR-37) ---------------
    -- Purpose: the valid branch.  Keep only rows that are valid and
    -- have a relationship type, and keep one row per (key, end date,
    -- start date) -- the latest created row.  Reads step 20, not
    -- step 30.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL2_S4_CONSOL AS
    SELECT r.*
      FROM WRK_TRS_REL2_S2_KEYED r
     WHERE r.is_valid AND r.rel_type_code IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY r.pkey_src_object, r.END_DT, r.BEGIN_DT
                                  ORDER BY r.CREATE_DT DESC NULLS FIRST) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL2_S4_CONSOL;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'CONSOLIDATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL2_S4_CONSOL', 'CREATED',
        'Valid member-to-PCP rows only, one row per (key, end date, start date) (BR-37). '
        || 'Read by the DST-preparation step.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 CONSOLIDATED', :l_rows) || CHR(10);

    -- ---- Step 50: PREPARE -- DST end date (BR-38) ------------------------
    -- Purpose: the timeline input.  dst_end_date is the DST-corrected
    -- end date (moves forward one hour on a daylight-saving change,
    -- via REF_DYLGHT_SVNGS_TM).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL2_S5_PREP AS
    WITH
    lkp_dst AS (SELECT * FROM TABLE(fn_snow_helper47_common()))
    SELECT c.*,
           /* TIMELINE */ fn_snow_helper35_common(c.BEGIN_DT, c.END_DT, d.DST IS NOT NULL)  AS dst_end_date
      FROM WRK_TRS_REL2_S4_CONSOL c
      LEFT JOIN lkp_dst d ON d.DST = DATEADD(hour, 2, c.END_DT);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL2_S5_PREP;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PREPARED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL2_S5_PREP', 'CREATED',
        'Consolidated rows with DST-corrected end date (BR-38). '
        || 'Read by the timeline-versioning step.',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PREPARED', :l_rows) || CHR(10);

    -- ---- Step 60: TIMELINE -- versions, ranking, guards (BR-38) ----------
    -- Purpose: the timeline output.  Open rows pass once; every
    -- end-dated row is emitted twice -- the closed version and an open
    -- copy with the end date removed.  VERSION_SEQ is re-numbered per
    -- key (start ascending, end descending, NULL high),
    -- TIMELINE_ACTION is 2 when end-dated, HUB_STATE_IND is 1 only on
    -- the open row with VERSION_SEQ 1, and uq_rel is the insert-only
    -- guard (key + version not already in the target).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL2_S6_TIMELINE AS
    WITH
    versions AS (
        SELECT p.*, p.dst_end_date AS tl_period_end_date FROM WRK_TRS_REL2_S5_PREP p
        UNION ALL
        SELECT p.*, NULL::TIMESTAMP_NTZ FROM WRK_TRS_REL2_S5_PREP p WHERE p.dst_end_date IS NOT NULL
    ),
    timeline AS (
        SELECT v.*,
               ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                  ORDER BY v.BEGIN_DT ASC NULLS LAST, v.tl_period_end_date DESC NULLS FIRST) AS tl_version_seq
          FROM versions v
    )
    SELECT t.*,
           IFF(t.tl_period_end_date IS NOT NULL, 2, NULL)                          AS tl_timeline_action,
           IFF(t.tl_period_end_date IS NULL AND t.tl_version_seq = 1, 1, NULL)     AS tl_hub_state_ind,
           /* BAD DATA: unique key (PKEY_SRC_OBJECT, VERSION_SEQ) not yet in the table */
           xr.PKEY_SRC_OBJECT IS NULL                                               AS uq_rel
      FROM timeline t
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_REL_PROV) xr
             ON xr.PKEY_SRC_OBJECT = t.pkey_src_object AND xr.VERSION_SEQ = t.tl_version_seq;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL2_S6_TIMELINE;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'TIMELINE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL2_S6_TIMELINE', 'CREATED',
        'Timeline versions (closed + open copy), re-numbered, with timeline action / hub state / insert-only guard (BR-38). '
        || 'Read by the provider-relationship publish branch.',
        NULL, 'Step 60 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 TIMELINE', :l_rows) || CHR(10);

    -- ---- Step 70: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-60 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The three INSERTs below are the three
    -- branches of the original INSERT ALL, in the same order, with the
    -- same column lists, values and WHERE conditions -- only the
    -- source changed, from the both_kinds CTE to steps 30 / 60.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 70a. Period_Start_Date_GT_Period_End_Date -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
            PERIOD_END_DATE, SRC_SYS_ID_3, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT 'TRS', INDV_ID, PROVIDER_NUM, :c_mapping, :l_run_ts, attr_dates, BEGIN_DT, END_DT, pty_rle_fk_2,
           exc_dates_code, exc_dates_desc, exc_dates_type
      FROM WRK_TRS_REL2_S3_ROUTER
     WHERE dates_reversed AND uq_exc_dates;
    l_rows := l_rows + SQLROWCOUNT;
    -- 70b. Default (key missing, period not reversed) -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, MAPPING_NAME, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, PERIOD_START_DATE,
            PERIOD_END_DATE, SRC_SYS_ID_1, SRC_SYS_ID_2, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
    SELECT 'TRS', :l_run_ts, :c_mapping, exc_default_code, exc_default_desc, exc_default_type, BEGIN_DT,
           END_DT, INDV_ID, PROVIDER_NUM, PROVIDER_NUM, attr_provider
      FROM WRK_TRS_REL2_S3_ROUTER
     WHERE NOT is_valid AND NOT dates_reversed AND uq_exc_default;
    l_rows := l_rows + SQLROWCOUNT;
    -- 70c. Valid records -> C_S_TRS_PTY_RLE_REL_PROV
    INSERT INTO C_S_TRS_PTY_RLE_REL_PROV
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE,
            SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, HIERARCHY_CODE, REL_TP,
            SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, ROWID_OBJECT, DELETED_IND, DELETED_DATE,
            DELETED_BY, UPDATED_BY, CREATOR)
    SELECT pkey_src_object, BEGIN_DT, tl_period_end_date, tl_version_seq, :l_run_ts, NULL, pkey_src_object,
           tl_hub_state_ind, pty_rle_fk_1, pty_rle_fk_2, rel_type_code, 'Member', :P_PCP_REL_TP, CREATE_DT,
           tl_period_end_date, tl_timeline_action, NULL, NULL, NULL, NULL, NULL, NULL
      FROM WRK_TRS_REL2_S6_TIMELINE
     WHERE uq_rel;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 70,
        'PUBLISH', 'COMPLETED',
        'C_S_TRS_PTY_RLE_REL_PROV, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid provider relationships and both exception classes. '
        || 'Count shown is the total rows inserted by all three INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 70 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
