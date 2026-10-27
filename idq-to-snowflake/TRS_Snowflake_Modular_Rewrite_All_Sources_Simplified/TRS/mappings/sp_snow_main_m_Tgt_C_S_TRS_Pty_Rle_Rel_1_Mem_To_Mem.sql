-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow
-- wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-36  Member-to-member relationships need both ends valid and a
--          known type: both members must be valid TRS members (one
--          source key per individual, MCI first), the relationship
--          type must translate through the PTY_REL crosswalk, and the
--          period must not be reversed.
--   BR-38  Relationship timelines are validated, not assumed: start
--          <= end (null end date = open), DST-corrected end dates,
--          end-dated rows emitted twice (closed + open copy),
--          VERSION_SEQ re-numbered per key.
--   BR-02  A failing relationship is not loaded, only logged; a row
--          can match several exception groups and is then logged once
--          per group.
--   BR-10  Relationships to non-valid members are not loaded and do
--          not raise an exception (they never reach the router, because
--          the source joins both ends to the valid-member spine).
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (min_pk -> src ->
--   keyed -> routed -> consolidated -> prepared -> versions -> ranked
--   -> timeline, plus router, unioned into both_kinds with a final
--   SELECT), one transaction, one log line at the end.  If it failed,
--   nothing told you which logical stage had finished.
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
--   Step 10  WRK_TRS_REL1_S1_SRC       relationship delta, both ends
--                                      joined to the valid-member
--                                      spine (one key per individual)
--   Step 20  WRK_TRS_REL1_S2_KEYED     type translated (PTY_REL),
--                                      party-role keys built,
--                                      relationship key + dates-
--                                      reversed flag
--   Step 30  WRK_TRS_REL1_S3_ROUTER    exception first-row flags +
--                                      exception descriptions/types
--            (branch: step 30 reads step 20 -- the exception branch)
--   Step 40  WRK_TRS_REL1_S4_CONSOL    valid rows only, one row per
--                                      (key, end date, start date)
--            (branch: step 40 reads step 20, NOT step 30 -- valid and
--             exception rows are two branches of the same keyed output)
--   Step 50  WRK_TRS_REL1_S5_PREP      latest update date + DST-
--                                      corrected end date
--   Step 60  WRK_TRS_REL1_S6_TIMELINE  timeline versions (closed +
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
--   WRK_TRS_REL1_S1_SRC, WRK_TRS_REL1_S2_KEYED, WRK_TRS_REL1_S3_ROUTER,
--   WRK_TRS_REL1_S4_CONSOL, WRK_TRS_REL1_S5_PREP, WRK_TRS_REL1_S6_TIMELINE.
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
--     DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_REL; the
--     Snowflake version instead skips keys already present (uq_rel).
--     A re-run therefore inserts nothing twice, but it also does not
--     remove rows that IDQ would have truncated away.
--   * Relationship foreign keys are based on source keys, not MDM
--     rowids, as in IDQ (keys are '<pty_pk>|Member').
--   * 'Invalid_Rel_Type' writes the looked-up code: the exception code
--     column in that INSERT is the code row looked up from
--     EXC_LOOKUP_CODE_VALUE, so it is NULL when that code is not
--     configured in the lookup table -- preserved.
--   * Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY,
--     CREATOR.  HUB_STATE_IND is 1 only on the open row with
--     VERSION_SEQ 1 (its input port is not fed, so all other rows
--     get NULL); PERIOD_REFERENCE_TIME is the (DST-corrected) end
--     date and TIMELINE_ACTION is 2 when end-dated, NULL when open.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (
    P_INDV_ID_ALT_ID_TP VARCHAR DEFAULT '007',  -- $INDV_ID_ALT_ID_TP (substituted into the source SQL)
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
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
    DROP TABLE IF EXISTS WRK_TRS_REL1_S1_SRC;
    DROP TABLE IF EXISTS WRK_TRS_REL1_S2_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_REL1_S3_ROUTER;
    DROP TABLE IF EXISTS WRK_TRS_REL1_S4_CONSOL;
    DROP TABLE IF EXISTS WRK_TRS_REL1_S5_PREP;
    DROP TABLE IF EXISTS WRK_TRS_REL1_S6_TIMELINE;

    -- ---- Step 10: SOURCE -- both ends valid (BR-36/10) -------------------
    -- Purpose: the relationship delta with exactly one source key per
    -- individual (MIN(pty_pk) from the valid-member spine, MCI record
    -- prioritised by the key ordering in the spine).  The inner joins
    -- mean a relationship to a non-valid member never appears here --
    -- and therefore never raises an exception downstream, by design.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL1_S1_SRC AS
    WITH
    min_pk AS (
        SELECT indv_id, MIN(pty_pk) pty_pk FROM STG_TRS_VALID_MEMBERS GROUP BY indv_id
    )
    SELECT rel.indv_id AS INDV_ID, rel.ref_indv_id AS REF_INDV_ID, rel.eff_begin_dt AS EFF_BEGIN_DT,
           rel.eff_end_dt AS EFF_END_DT, rel.hist_nav_ind AS HIST_NAV_IND,
           rel.relationship_type_cd AS RELATIONSHIP_TYPE_CD, pk1.pty_pk AS PTY_PKEY, pk2.pty_pk AS REF_PTY_PKEY,
           :P_INDV_ID_ALT_ID_TP AS PTY_ALT_ID_TP, rel.create_dt AS CREATE_DT, rel.update_dt AS UPDATE_DT
      FROM STG_TRS_D_DC_RELATIONSHIPS rel
      JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
      JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL1_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_RELATIONSHIPS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL1_S1_SRC', 'CREATED',
        'Relationship delta, both ends joined to the valid-member spine (BR-36/10). '
        || 'Read by the keying step; never re-read the raw sources after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_RELATIONSHIPS', :l_rows) || CHR(10);

    -- ---- Step 20: KEYING -- translate type, build keys (BR-36) -----------
    -- Purpose: translate the relationship type through the PTY_REL
    -- crosswalk, build the two party-role keys ('<pty_pk>|Member'),
    -- build the relationship staging key, and flag reversed periods
    -- (begin after end).  A NULL translated type or a NULL key is
    -- preserved as NULL here -- the router step decides what it means.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL1_S2_KEYED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    keyed AS (
        SELECT s.*,
               pt.MSTR_CODE_VALUE                                                       AS rel_type_code,
               IFF(s.PTY_PKEY IS NULL, NULL, TRIM(s.PTY_PKEY) || '|Member')             AS pty_rle_fk_1,
               IFF(s.REF_PTY_PKEY IS NULL, NULL, TRIM(s.REF_PTY_PKEY) || '|Member')     AS pty_rle_fk_2
          FROM WRK_TRS_REL1_S1_SRC s
          LEFT JOIN lkp_cv pt ON pt.CODE_TYPE = 'PTY_REL' AND pt.SRC_SYS = 'TRS'
                             AND pt.SRC_CODE_VALUE = s.RELATIONSHIP_TYPE_CD
    )
    SELECT k.*,
           NVL(k.pty_rle_fk_1, '') || '|' || NVL(k.pty_rle_fk_2, '') || '|' || NVL(k.rel_type_code, '')
                                                                                    AS pkey_src_object,
           /* VALIDATION */ NVL(k.EFF_BEGIN_DT > k.EFF_END_DT, FALSE)              AS dates_reversed
      FROM keyed k;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL1_S2_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL1_S2_KEYED', 'CREATED',
        'Relationships with translated type, party-role keys, staging key and reversed-period flag (BR-36). '
        || 'Read by both the router step and the consolidation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 KEYED', :l_rows) || CHR(10);

    -- ---- Step 30: ROUTER -- exception flags + descriptions (BR-02) ------
    -- Purpose: the exception branch.  For every keyed row, set the
    -- first-row-per-exception-key flags (uq_exc_*) and resolve the
    -- exception descriptions/types and label constants exactly as the
    -- original final SELECT did, so the publish step can copy them
    -- straight into EXC_STG_BAD_REC_MEMB.  A row can be flagged for
    -- several exception groups at once; the publish step writes one
    -- exception row per group it matches.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL1_S3_ROUTER AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    router AS (
        SELECT r.*,
               /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.pty_rle_fk_1 IS NULL, r.INDV_ID, r.REF_INDV_ID, r.rel_type_code
                                      ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_member,
               ROW_NUMBER() OVER (PARTITION BY r.pty_rle_fk_2 IS NULL, r.INDV_ID, r.REF_INDV_ID, r.rel_type_code
                                      ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_ref,
               ROW_NUMBER() OVER (PARTITION BY r.rel_type_code IS NULL, r.INDV_ID, r.REF_INDV_ID,
                                               r.RELATIONSHIP_TYPE_CD ORDER BY r.CREATE_DT DESC) = 1 AS uq_exc_type,
               ROW_NUMBER() OVER (PARTITION BY r.dates_reversed, r.INDV_ID, r.REF_INDV_ID, r.RELATIONSHIP_TYPE_CD
                                      ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_dates
          FROM WRK_TRS_REL1_S2_KEYED r
    )
    SELECT r.*,
           'Member Relationship'                         AS rel_type_code_label,
           'Member'                                      AS hierarchy_code,
           'Relationship Type'                           AS attr_rel_type,
           'Effective Date'                              AS attr_dates,
           'Invalid_Member'                              AS exc_member_code,
           xm.EXCEPTION_DESC                             AS exc_member_desc,
           xm.EXCEPTION_TYPE                             AS exc_member_type,
           'Invalid_Ref_Member'                          AS exc_ref_code,
           xf.EXCEPTION_DESC                             AS exc_ref_desc,
           xf.EXCEPTION_TYPE                             AS exc_ref_type,
           xt.EXCEPTION_CODE                             AS exc_type_lkp_code,
           xt.EXCEPTION_DESC                             AS exc_type_desc,
           xt.EXCEPTION_TYPE                             AS exc_type_type,
           'Period_Start_Date_>_Period_End_Date'         AS exc_dates_code,
           xd.EXCEPTION_DESC                             AS exc_dates_desc,
           xd.EXCEPTION_TYPE                             AS exc_dates_type
      FROM router r
      LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = 'Invalid_Member'
      LEFT JOIN lkp_exc xf ON xf.EXCEPTION_CODE = 'Invalid_Ref_Member'
      LEFT JOIN lkp_exc xt ON xt.EXCEPTION_CODE = 'Invalid_Rel_Type'
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date';
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL1_S3_ROUTER;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ROUTER_EXCEPTIONS', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_TRS_REL1_S3_ROUTER', 'CREATED',
        'Router rows: exception first-row flags with descriptions/types resolved (BR-02). '
        || 'Read by the exception publish branches only; a row may match several groups.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ROUTER', :l_rows) || CHR(10);

    -- ---- Step 40: CONSOLIDATION -- valid rows only (BR-36) ---------------
    -- Purpose: the valid branch.  Keep only rows with both keys, a
    -- translated type and a non-reversed period, and keep one row per
    -- (key, end date, start date) -- the latest created/updated row.
    -- Reads step 20, not step 30.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL1_S4_CONSOL AS
    SELECT r.*
      FROM WRK_TRS_REL1_S2_KEYED r
     WHERE r.pty_rle_fk_1 IS NOT NULL AND r.pty_rle_fk_2 IS NOT NULL AND r.rel_type_code IS NOT NULL
       AND NOT r.dates_reversed
    QUALIFY ROW_NUMBER() OVER (PARTITION BY r.pkey_src_object, r.EFF_END_DT, r.EFF_BEGIN_DT
                                  ORDER BY r.CREATE_DT DESC NULLS FIRST, r.UPDATE_DT DESC NULLS FIRST) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL1_S4_CONSOL;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'CONSOLIDATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL1_S4_CONSOL', 'CREATED',
        'Valid relationships only, one row per (key, end date, start date) (BR-36). '
        || 'Read by the DST-preparation step.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 CONSOLIDATED', :l_rows) || CHR(10);

    -- ---- Step 50: PREPARE -- latest update + DST end date (BR-38) -------
    -- Purpose: the timeline inputs.  SRC_LAST_UPD_DT is the later of
    -- create / update (or whichever is present), and dst_end_date is
    -- the DST-corrected end date (moves forward one hour on a
    -- daylight-saving change, via REF_DYLGHT_SVNGS_TM).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL1_S5_PREP AS
    WITH
    lkp_dst AS (SELECT * FROM TABLE(fn_snow_helper47_common()))
    SELECT c.*,
           IFF(c.CREATE_DT IS NOT NULL AND c.UPDATE_DT IS NOT NULL, GREATEST(c.CREATE_DT, c.UPDATE_DT),
               NVL(c.CREATE_DT, c.UPDATE_DT))                                      AS src_last_upd_dt,
           /* TIMELINE */ fn_snow_helper35_common(c.EFF_BEGIN_DT, c.EFF_END_DT, d.DST IS NOT NULL) AS dst_end_date
      FROM WRK_TRS_REL1_S4_CONSOL c
      LEFT JOIN lkp_dst d ON d.DST = DATEADD(hour, 2, c.EFF_END_DT);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL1_S5_PREP;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PREPARED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL1_S5_PREP', 'CREATED',
        'Consolidated rows with latest update date and DST-corrected end date (BR-38). '
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
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_REL1_S6_TIMELINE AS
    WITH
    versions AS (
        SELECT p.*, p.dst_end_date AS tl_period_end_date FROM WRK_TRS_REL1_S5_PREP p
        UNION ALL
        SELECT p.*, NULL::TIMESTAMP_NTZ FROM WRK_TRS_REL1_S5_PREP p WHERE p.dst_end_date IS NOT NULL
    ),
    ranked AS (
        SELECT v.*,
               ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                  ORDER BY v.EFF_BEGIN_DT ASC NULLS LAST,
                                           v.tl_period_end_date DESC NULLS FIRST)       AS tl_version_seq
          FROM versions v
    )
    SELECT k.*,
           IFF(k.tl_period_end_date IS NOT NULL, 2, NULL)                          AS tl_timeline_action,
           IFF(k.tl_period_end_date IS NULL AND k.tl_version_seq = 1, 1, NULL)     AS tl_hub_state_ind,
           /* BAD DATA: unique key (PKEY_SRC_OBJECT, VERSION_SEQ) not yet in the table */
           xr.PKEY_SRC_OBJECT IS NULL                                               AS uq_rel
      FROM ranked k
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_REL) xr
             ON xr.PKEY_SRC_OBJECT = k.pkey_src_object AND xr.VERSION_SEQ = k.tl_version_seq;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_REL1_S6_TIMELINE;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'TIMELINE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_REL1_S6_TIMELINE', 'CREATED',
        'Timeline versions (closed + open copy), re-numbered, with timeline action / hub state / insert-only guard (BR-38). '
        || 'Read by the relationship publish branch.',
        NULL, 'Step 60 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 TIMELINE', :l_rows) || CHR(10);

    -- ---- Step 70: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-60 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The five INSERTs below are the five branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the both_kinds CTE to steps 30 / 60.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 70a. Invalid_Main_Alt_Id -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
            PERIOD_END_DATE, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
    SELECT 'TRS', :l_run_ts, :c_mapping, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
           exc_member_desc, exc_member_type, exc_member_code
      FROM WRK_TRS_REL1_S3_ROUTER
     WHERE pty_rle_fk_1 IS NULL AND uq_exc_member;
    l_rows := l_rows + SQLROWCOUNT;
    -- 70b. Invalid_Ref_Alt_Id -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
            PERIOD_END_DATE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT 'TRS', :l_run_ts, :c_mapping, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
           exc_ref_code, exc_ref_desc, exc_ref_type
      FROM WRK_TRS_REL1_S3_ROUTER
     WHERE pty_rle_fk_2 IS NULL AND uq_exc_ref;
    l_rows := l_rows + SQLROWCOUNT;
    -- 70c. Invalid_Lookup -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
    SELECT 'TRS', INDV_ID, REF_INDV_ID, :c_mapping, :l_run_ts, RELATIONSHIP_TYPE_CD, RELATIONSHIP_TYPE_CD,
           attr_rel_type, EFF_BEGIN_DT, EFF_END_DT, exc_type_type, exc_type_desc, exc_type_lkp_code
      FROM WRK_TRS_REL1_S3_ROUTER
     WHERE rel_type_code IS NULL AND uq_exc_type;
    l_rows := l_rows + SQLROWCOUNT;
    -- 70d. Period_Start_Dt_GT_Period_End_Date -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_NAME,
            PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT 'TRS', INDV_ID, REF_INDV_ID, :c_mapping, :l_run_ts, RELATIONSHIP_TYPE_CD, attr_dates,
           EFF_BEGIN_DT, EFF_END_DT, exc_dates_code, exc_dates_desc, exc_dates_type
      FROM WRK_TRS_REL1_S3_ROUTER
     WHERE dates_reversed AND uq_exc_dates;
    l_rows := l_rows + SQLROWCOUNT;
    -- 70e. Valid relationships -> C_S_TRS_PTY_RLE_REL
    INSERT INTO C_S_TRS_PTY_RLE_REL
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY,
            CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE,
            HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, EFF_BEGIN_DT, tl_period_end_date, tl_version_seq,
           tl_period_end_date, tl_timeline_action, :l_run_ts, NULL, CREATE_DT, NULL, pkey_src_object,
           tl_hub_state_ind, pty_rle_fk_1, pty_rle_fk_2, rel_type_code_label, hierarchy_code, rel_type_code,
           src_last_upd_dt
      FROM WRK_TRS_REL1_S6_TIMELINE
     WHERE uq_rel;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 70,
        'PUBLISH', 'COMPLETED',
        'C_S_TRS_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid relationships and all four exception classes. '
        || 'Count shown is the total rows inserted by all five INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 70 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
