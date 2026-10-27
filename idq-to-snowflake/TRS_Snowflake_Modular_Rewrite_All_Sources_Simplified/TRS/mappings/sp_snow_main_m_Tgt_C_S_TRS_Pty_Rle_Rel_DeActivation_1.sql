-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1, workflow
-- wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-41  A relationship is deactivated when its keys are gone or its
--          hub state already says so: read the relationship delta
--          (STG_TRS_D_DC_RELATIONSHIPS_A), translate the type through
--          the PTY_REL crosswalk, check the MDM cross-reference
--          (C_B_PTY_RLE_REL_XREF), derive MERGE_YN / MASTER_RECORD_YN /
--          SOFT_DELETE_YN, filter out keys already logged, and write
--          new rows to STG_TRS_DEACTIVATED_RELATIONSHIPS.
--          Relationships already soft-deleted in the hub
--          (SOFT_DELETE_YN = 'Y') are logged as PROCESSED_YN = 'Y' in
--          IDQ so they are never actioned -- see the Parity notes for
--          how the Snowflake version handles PROCESSED_YN.
--   BR-11  One source key per individual, MCI first: the min_pk pattern
--          (MIN(pty_pk) per indv_id from STG_TRS_VALID_MEMBERS) is used
--          for both ends of every relationship.
--   BR-50  PROCESSED_YN is the idempotency key for the whole deactivation
--          process: rows already logged as unprocessed are not logged
--          again here.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (min_pk -> src ->
--   keyed -> xref_obj -> xref_key -> xref -> xref_one -> final SELECT
--   with the already-logged guard and the cross-reference-exists filter),
--   one transaction, one log line at the end.  If it failed, nothing
--   told you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT, written as a single
--   INSERT from the last work table inside ONE transaction.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_RELDEACT_S10_MINPK   one source key per individual (min_pk)
--   Step 20  WRK_TRS_RELDEACT_S20_SRC     relationship delta, both ends resolved
--                                        through step 10
--   Step 30  WRK_TRS_RELDEACT_S30_KEYED   PTY_REL translation + composite
--                                        PKEY_SRC_OBJECT (Exp_Gen_PKEY)
--   Step 40  WRK_TRS_RELDEACT_S40_XREF    MDM cross-reference, one row per
--                                        source key (return-any), with
--                                        merge / master / soft-delete flags
--   Step 50  WRK_TRS_RELDEACT_S50_READY   publish-ready rows: not already logged
--                                        as unprocessed AND present in the MDM
--   Step 60  PUBLISH                     STG_TRS_DEACTIVATED_RELATIONSHIPS,
--                                        in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_RELDEACT_S10_MINPK, WRK_TRS_RELDEACT_S20_SRC,
--   WRK_TRS_RELDEACT_S30_KEYED, WRK_TRS_RELDEACT_S40_XREF,
--   WRK_TRS_RELDEACT_S50_READY.  They live in the same schema as the
--   targets (unqualified names, as in the original code), are prefixed
--   WRK_TRS_, and are registered in JOB_CONTROL_ETL at creation and
--   at drop.  They survive a session crash (TRANSIENT, not TEMP), which
--   is what makes inspection after a run possible; a pure session TEMP table would
--   vanish with the session and would be gone after a crash.  A
--   Snowflake CURSOR was NOT used: cursors process row by row, and every
--   step here is set-based by design -- the work table IS the result
--   set, held as a table instead of in memory, so it can be counted,
--   inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  The IDQ mapping has no delete target here
--     either -- the original Snowflake comment notes the mapping
--     description also mentions removing relationships from a valid
--     list, but the IDQ mapping has no such target, so nothing is
--     removed in either version.
--   * PROCESSED_YN is NOT in the INSERT column list, exactly as in the
--     original: it is left to the column default of
--     STG_TRS_DEACTIVATED_RELATIONSHIPS.  IDQ writes new rows as
--     PROCESSED_YN = 'N' (BR-50) and already-soft-deleted rows as 'Y'.
--     If the Snowflake column default is 'N', behaviour matches IDQ for
--     new rows; if it is NULL, the later CopyList still picks the rows
--     up (it treats NULL as unprocessed, nvl(PROCESSED_YN,'N') <> 'Y'),
--     but any process that tests PROCESSED_YN = 'N' exactly would miss
--     them.  Confirm the column default before relying on this step.
--   * SOFT_DELETE_YN is derived in step 40 (MAX(HUB_STATE_IND) = -1 per
--     hub object) but is NOT a column of the target table, so it is not
--     published -- exactly as in the original, where it is computed in
--     the xref CTE and then not selected.  The already-soft-deleted
--     shortcut in IDQ (log as PROCESSED_YN = 'Y', never actioned) is
--     therefore NOT reproduced as a separate 'Y' row here; such rows
--     are simply not distinguished from new rows unless the column
--     default or a later step does it.
--   * An untranslated relationship type gives a key ending in '|', which
--     finds no cross-reference and is dropped by the step-50 filter
--     (MIN_ROWID_XREF NOT NULL), as in the original.
--   * xref_one is "return any row" per PKEY_SRC_OBJECT: the first row by
--     ROWID_OBJECT.  If one source key maps to more than one hub object,
--     which object is picked is order-dependent, as in the original.
--   * The already-logged guard (step 50) checks only rows logged as
--     PROCESSED_YN = 'N' -- a key logged as 'Y' (already processed) is
--     not blocked by this guard, but it is blocked in practice by the
--     cross-reference filter only if it is no longer in the hub.
--
-- SIGNATURE
--   The original procedure took no parameters, so there are no original
--   parameters to preserve.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 (
    P_JOB_RUN_ID  VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1';
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
    DROP TABLE IF EXISTS WRK_TRS_RELDEACT_S10_MINPK;
    DROP TABLE IF EXISTS WRK_TRS_RELDEACT_S20_SRC;
    DROP TABLE IF EXISTS WRK_TRS_RELDEACT_S30_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_RELDEACT_S40_XREF;
    DROP TABLE IF EXISTS WRK_TRS_RELDEACT_S50_READY;


    -- ---- Step 10: ONE SOURCE KEY PER INDIVIDUAL (BR-11) -----------------
    -- Purpose: min_pk -- MIN(pty_pk) per indv_id from
    -- STG_TRS_VALID_MEMBERS, prioritising the MCI record.  This table is
    -- joined twice in step 20 (once per end of the relationship), so it
    -- is materialised once instead of computed twice.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_RELDEACT_S10_MINPK AS
    SELECT indv_id, MIN(pty_pk) pty_pk FROM STG_TRS_VALID_MEMBERS GROUP BY indv_id;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_RELDEACT_S10_MINPK;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'MIN_PK', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_RELDEACT_S10_MINPK', 'CREATED',
        'One source key per individual from the valid-member spine (BR-11). '
        || 'Read twice by the source step, once per relationship end.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 MIN_PK', :l_rows) || CHR(10);

    -- ---- Step 20: RELATIONSHIP DELTA, BOTH ENDS RESOLVED ----------------
    -- Purpose: Read_STG_TRS_D_DC_RELATIONSHIPS_A -- the relationship
    -- delta, inner-joined through step 10 on both ends.  A relationship
    -- whose member or reference member is not a valid member is dropped
    -- here by the inner joins, before any key is built.  SRC_SYS is
    -- 'TRS' for every row.  Reads ONLY step 10 (twice).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_RELDEACT_S20_SRC AS
    SELECT rel.indv_id AS INDV_ID, rel.ref_indv_id AS REF_INDV_ID, rel.eff_begin_dt AS EFF_BEGIN_DT,
           rel.eff_end_dt AS EFF_END_DT, rel.relationship_type_cd AS RELATIONSHIP_TYPE_CD, pk1.pty_pk AS PTY_PKEY,
           pk2.pty_pk AS REF_PTY_PKEY, 'TRS' AS SRC_SYS
      FROM STG_TRS_D_DC_RELATIONSHIPS_A rel
      JOIN WRK_TRS_RELDEACT_S10_MINPK pk1 ON rel.indv_id = pk1.indv_id
      JOIN WRK_TRS_RELDEACT_S10_MINPK pk2 ON rel.ref_indv_id = pk2.indv_id;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_RELDEACT_S20_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'REL_SRC', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_RELDEACT_S20_SRC', 'CREATED',
        'Relationship delta with both ends resolved through the valid-member spine (BR-41, BR-11). '
        || 'Read by the keying step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 REL_SRC', :l_rows) || CHR(10);

    -- ---- Step 30: PTY_REL TRANSLATION + COMPOSITE KEY (BR-41) -----------
    -- Purpose: Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL) +
    -- Exp_Gen_PKEY.  Each end becomes '<party key>|Member' (NULL if the
    -- key is NULL -- not possible after step 20's inner joins, but kept
    -- as written), and the composite key is member | ref member |
    -- master type.  An untranslated type leaves the key ending in '|',
    -- which finds no cross-reference and is dropped in step 50.
    -- Reads ONLY step 20.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_RELDEACT_S30_KEYED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT s.*,
           IFF(s.PTY_PKEY IS NULL, NULL, TRIM(s.PTY_PKEY) || '|Member')               AS pty_rle_fk_1,
           IFF(s.REF_PTY_PKEY IS NULL, NULL, TRIM(s.REF_PTY_PKEY) || '|Member')       AS pty_rle_fk_2,
           NVL(IFF(s.PTY_PKEY IS NULL, NULL, TRIM(s.PTY_PKEY) || '|Member'), '') || '|'
           || NVL(IFF(s.REF_PTY_PKEY IS NULL, NULL, TRIM(s.REF_PTY_PKEY) || '|Member'), '') || '|'
           || NVL(pt.MSTR_CODE_VALUE, '')                                             AS pkey_src_object
      FROM WRK_TRS_RELDEACT_S20_SRC s
      LEFT JOIN lkp_cv pt ON pt.CODE_TYPE = 'PTY_REL' AND pt.SRC_SYS = s.SRC_SYS
                         AND pt.SRC_CODE_VALUE = s.RELATIONSHIP_TYPE_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_RELDEACT_S30_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'KEYED_REL', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_RELDEACT_S30_KEYED', 'CREATED',
        'Relationships with PTY_REL translation and composite PKEY_SRC_OBJECT (BR-41). '
        || 'Read by the ready step, which joins the cross-reference.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 KEYED_REL', :l_rows) || CHR(10);

    -- ---- Step 40: MDM CROSS-REFERENCE, ONE ROW PER SOURCE KEY ----------
    -- Purpose: Lkp_C_B_PTY_RLE_REL_XREF (custom lookup SQL, written here
    -- as grouped joins, as in the original).  Per hub object: the count
    -- of distinct source keys (SRC_PKEY_CT) and the maximum hub state;
    -- per source key: the lowest ROWID_XREF.  From those: MERGE_YN =
    -- 'Y' when more than one distinct source key shares a hub object,
    -- MASTER_RECORD_YN = 'Y' when ROWID_OBJECT = ORIG_ROWID_OBJECT,
    -- SOFT_DELETE_YN = 'Y' when MAX(HUB_STATE_IND) = -1.  Then
    -- xref_one keeps one row per PKEY_SRC_OBJECT (first by
    -- ROWID_OBJECT) -- the lookup's "return any row".  This table is
    -- independent of steps 10-30 (it reads only C_B_PTY_RLE_REL_XREF),
    -- but it is a step in its own right so its row count and contents
    -- can be inspected before the ready step joins it.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_RELDEACT_S40_XREF AS
    WITH
    xref_obj AS (
        SELECT ROWID_OBJECT, COUNT(DISTINCT PKEY_SRC_OBJECT) AS SRC_PKEY_CT, MAX(HUB_STATE_IND) AS MAX_HUB_STATE_IND
          FROM C_B_PTY_RLE_REL_XREF
         GROUP BY ROWID_OBJECT
    ),
    xref_key AS (
        SELECT PKEY_SRC_OBJECT, MIN(ROWID_XREF) AS MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF
         GROUP BY PKEY_SRC_OBJECT
    ),
    xref AS (
        SELECT DISTINCT t.ROWID_OBJECT, t.PKEY_SRC_OBJECT, t.ROWID_SYSTEM, o.SRC_PKEY_CT,
               IFF(o.SRC_PKEY_CT > 1, 'Y', 'N')                          AS MERGE_YN,
               IFF(t.ROWID_OBJECT = t.ORIG_ROWID_OBJECT, 'Y', 'N')        AS MASTER_RECORD_YN,
               IFF(o.MAX_HUB_STATE_IND = -1, 'Y', 'N')                    AS SOFT_DELETE_YN,
               k.MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF t
          JOIN xref_obj o ON o.ROWID_OBJECT = t.ROWID_OBJECT
          JOIN xref_key k ON k.PKEY_SRC_OBJECT = t.PKEY_SRC_OBJECT
    )
    SELECT * FROM xref
    QUALIFY ROW_NUMBER() OVER (PARTITION BY PKEY_SRC_OBJECT ORDER BY ROWID_OBJECT) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_RELDEACT_S40_XREF;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'XREF_ONE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_RELDEACT_S40_XREF', 'CREATED',
        'MDM cross-reference, one row per source key, with merge / master / soft-delete flags (BR-41). '
        || 'Read by the ready step. SOFT_DELETE_YN is derived here but not published (see Parity notes).',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 XREF_ONE', :l_rows) || CHR(10);

    -- ---- Step 50: READY -- not already logged AND present in the MDM ---
    -- Purpose: the original final SELECT, as a table.
    -- Lookup_STG_TRS_DEACTIVATED_RELATIONSHIPS (unprocessed rows only,
    -- PROCESSED_YN = 'N') + Fil_New_Deactivations: keep only rows whose
    -- key is NOT already logged as unprocessed (d.PKEY_SRC_OBJECT IS
    -- NULL) AND whose key exists in the MDM (x.MIN_ROWID_XREF IS NOT
    -- NULL -- this is what drops untranslated types, whose key ends in
    -- '|' and finds no cross-reference).  LOAD_DATE = run start;
    -- PROCESSED_YN is not selected (left to the column default -- see
    -- Parity notes).  This table is in target column order, so step 60
    -- is a plain INSERT ... SELECT.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_RELDEACT_S50_READY AS
    SELECT k.INDV_ID AS INDV_ID, k.REF_INDV_ID AS REF_INDV_ID,
           k.pty_rle_fk_1 AS PTY_RLE_FK_1, k.pty_rle_fk_2 AS PTY_RLE_FK_2,
           k.RELATIONSHIP_TYPE_CD AS REL_TYPE_CODE, x.SRC_PKEY_CT AS SRC_PKEY_CT,
           :l_run_ts AS LOAD_DATE, k.pkey_src_object AS PKEY_SRC_OBJECT,
           x.ROWID_OBJECT AS ROWID_OBJECT, x.MASTER_RECORD_YN AS MASTER_RECORD_YN,
           TRIM(x.MERGE_YN) AS MERGED_YN, k.SRC_SYS AS ROWID_SYSTEM, x.MIN_ROWID_XREF AS ROWID_XREF
      FROM WRK_TRS_RELDEACT_S30_KEYED k
      LEFT JOIN WRK_TRS_RELDEACT_S40_XREF x ON x.PKEY_SRC_OBJECT = k.pkey_src_object
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM STG_TRS_DEACTIVATED_RELATIONSHIPS
                  WHERE PROCESSED_YN = 'N' AND PKEY_SRC_OBJECT IS NOT NULL) d
             ON d.PKEY_SRC_OBJECT = k.pkey_src_object
     WHERE d.PKEY_SRC_OBJECT IS NULL
       AND x.MIN_ROWID_XREF IS NOT NULL;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_RELDEACT_S50_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'READY_TO_PUBLISH', 'COMPLETED', 'STG_TRS_DEACTIVATED_RELATIONSHIPS', :l_rows, NULL,
        'WRK_TRS_RELDEACT_S50_READY', 'CREATED',
        'Publish-ready deactivated relationships: not already logged as unprocessed, present in the MDM (BR-41, BR-50). '
        || 'Published in step 60. PROCESSED_YN left to the column default (see Parity notes).',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 60: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction.  If the INSERT fails, it rolls
    -- back, the checkpoints for steps 10-50 (already committed) survive,
    -- the work tables survive, and the run must be restarted from the beginning (step 5 cleanup, then step 10) 60.
    -- The INSERT below is the original INSERT, with the source changed
    -- from the keyed/xref CTEs to step 50.  No TRUNCATE, no DELETE, and
    -- PROCESSED_YN is not set here (column default -- see Parity notes).
    BEGIN TRANSACTION;
    INSERT INTO STG_TRS_DEACTIVATED_RELATIONSHIPS
           (INDV_ID, REF_INDV_ID, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, SRC_PKEY_CT, LOAD_DATE, PKEY_SRC_OBJECT,
            ROWID_OBJECT, MASTER_RECORD_YN, MERGED_YN, ROWID_SYSTEM, ROWID_XREF)
    SELECT INDV_ID, REF_INDV_ID, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, SRC_PKEY_CT, LOAD_DATE, PKEY_SRC_OBJECT,
           ROWID_OBJECT, MASTER_RECORD_YN, MERGED_YN, ROWID_SYSTEM, ROWID_XREF
      FROM WRK_TRS_RELDEACT_S50_READY;
    l_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'PUBLISH', 'COMPLETED', 'STG_TRS_DEACTIVATED_RELATIONSHIPS', :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: new deactivation log rows for relationships (BR-41). '
        || 'Count shown is rows inserted. PROCESSED_YN left to the column default.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 PUBLISH (STG_TRS_DEACTIVATED_RELATIONSHIPS)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
