-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty_Rle_Rel, workflow wf_FSS_Stage_Load.
--
-- What this mapping does, in plain words: it loads relationships
-- between FSS clients (one source row per direction) into the
-- party-role relationship table. Both parties in a relationship must
-- be off the deactivation list. A relationship whose code does not
-- translate in the code-value lookup is not loaded, only logged as an
-- exception.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> coded
--   -> typed -> final), one transaction, one log line at the end.
--   If it failed, nothing told you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   No step before publish writes to a final target, so the target
--   read in a later step (keys already in the relationship table)
--   still sees the same target state as the original single statement
--   did.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_FSS_REL_S1_SRC    source relationships, both parties
--                                  off the deactivation list
--   Step 20  WRK_FSS_REL_S2_CODED  relationship code built (missing
--                                  code defaults to CAREGIVER) with
--                                  gender, direction code type and
--                                  both role keys
--   Step 30  WRK_FSS_REL_S3_TYPED  relationship code translated through
--                                  the code-value lookup
--   Step 40  WRK_FSS_REL_S4_FINAL  relationship key, constants,
--                                  exception details, insert-only
--                                  guards
--   Step 50  PUBLISH               targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_FSS_REL_S1_SRC, WRK_FSS_REL_S2_CODED, WRK_FSS_REL_S3_TYPED,
--   WRK_FSS_REL_S4_FINAL.  They live in the same schema as the targets
--   (unqualified names, as in the original code), are prefixed
--   WRK_FSS_, and are registered in the shared job-control table at
--   creation.  They survive a session crash (TRANSIENT, not TEMP),
--   which is what makes inspection after a run possible.  A Snowflake
--   CURSOR was NOT used: cursors process row by row, and every step
--   here is set-based by design -- the work table IS the result set,
--   held as a table instead of in memory, so it can be counted and
--   inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  The IDQ truncate of the relationship table
--     is NOT performed; keys already present are skipped instead
--     (uq_rel guard).  A re-run therefore inserts nothing twice, but
--     it also does not remove rows that IDQ would have truncated away.
--   * PRESERVED: an untranslated relationship is logged with the
--     looked-up exception code, which is NULL when the
--     'Invalid_Relationship' code is not configured in the exception
--     catalogue.
--   * PRESERVED: the direction rule -- 'To Child' rows use the related
--     party's gender and code type REL_TP, other rows use the party's
--     own gender and code type INVERSE_REL -- exactly as in the
--     original.
--   * Version sequence is 1 and the period start date is the
--     relationship create date, exactly as in the original.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Rel';
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
    DROP TABLE IF EXISTS WRK_FSS_REL_S1_SRC;
    DROP TABLE IF EXISTS WRK_FSS_REL_S2_CODED;
    DROP TABLE IF EXISTS WRK_FSS_REL_S3_TYPED;
    DROP TABLE IF EXISTS WRK_FSS_REL_S4_FINAL;

    -- ---- Step 10: SOURCE + REMOVE DEACTIVATED ------------------------------
    -- Purpose: the relationships to process -- neither party on the
    -- deactivation list.  Every later step reads this table, never the
    -- raw source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_REL_S1_SRC AS
    SELECT r.RELATION_DIRECTION, r.RELN_DT_LAST_UPDATE, r.RELN_DT_CREATED, r.ID_CLIENT, r.CD_RELTSHP_TO_TC,
           r.PTY_SRC_KEY, r.RELN_PTY_SRC_KEY, r.RELN_CD_GENDER, r.CD_GENDER, r.RELN_ID_CLIENT,
           r.ID_REGISTRATION
      FROM V_FSS_ETL_SRC_RELATIONS r
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = r.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = r.RELN_PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_REL_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_REL_S1_SRC', 'CREATED',
        'Source relationships with both parties off the deactivation list. '
        || 'Read by the coding step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: CODE -------------------------------------------------------
    -- Purpose: build the relationship code (missing code defaults to
    -- CAREGIVER, joined to the related party's gender for 'To Child'
    -- rows and the party's own gender otherwise), pick the direction
    -- code type, and build both role keys.  Reads ONLY
    -- WRK_FSS_REL_S1_SRC.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_REL_S2_CODED AS
    SELECT s.*,
           NVL(s.CD_RELTSHP_TO_TC, 'CAREGIVER') || '|'
           || NVL(IFF(s.RELATION_DIRECTION = 'To Child', s.RELN_CD_GENDER, s.CD_GENDER), '') AS relation_cd,
           IFF(s.RELATION_DIRECTION = 'To Child', 'REL_TP', 'INVERSE_REL')                    AS code_type,
           IFF(s.RELATION_DIRECTION = 'To Child', s.RELN_CD_GENDER, s.CD_GENDER)              AS out_gender_cd,
           NVL(IFF(s.RELATION_DIRECTION = 'To Child', s.RELN_PTY_SRC_KEY, s.PTY_SRC_KEY), '') || '|Member'
                                                                                              AS rel_fk_1,
           NVL(IFF(s.RELATION_DIRECTION = 'To Child', s.PTY_SRC_KEY, s.RELN_PTY_SRC_KEY), '') || '|Member'
                                                                                              AS rel_fk_2
      FROM WRK_FSS_REL_S1_SRC s;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_REL_S2_CODED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'CODED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_REL_S2_CODED', 'CREATED',
        'Relationships with the relationship code, direction code type, output gender and both role keys built. '
        || 'Read by the translation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 CODED', :l_rows) || CHR(10);

    -- ---- Step 30: TRANSLATE ----------------------------------------------------
    -- Purpose: translate the relationship code through the code-value
    -- lookup for the direction's code type.  Rows with no translation
    -- stay in the table with a blank translated code -- they become
    -- exceptions in step 40, not loads.  Reads ONLY
    -- WRK_FSS_REL_S2_CODED.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_REL_S3_TYPED AS
    SELECT c.*, lk.MSTR_REF_CODE AS mstr_ref_code
      FROM WRK_FSS_REL_S2_CODED c
      LEFT JOIN (SELECT l.CODE_TYPE, l.SRC_CODE_VALUE, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                  WHERE l.CODE_TYPE IN ('REL_TP', 'INVERSE_REL') AND l.SRC_SYS = 'FSS'
                QUALIFY ROW_NUMBER() OVER (PARTITION BY l.CODE_TYPE, l.SRC_CODE_VALUE
                                               ORDER BY l.MSTR_REF_CODE) = 1) lk
             ON lk.SRC_CODE_VALUE = c.relation_cd AND lk.CODE_TYPE = c.code_type;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_REL_S3_TYPED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'TYPED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_REL_S3_TYPED', 'CREATED',
        'Relationships with the translated relationship code attached (blank when untranslated). '
        || 'Read by the final step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 TYPED', :l_rows) || CHR(10);

    -- ---- Step 40: FINAL ---------------------------------------------------------
    -- Purpose: build the relationship key and constants, resolve the
    -- exception details, and set the insert-only guards (first row per
    -- relationship / exception key, key not already in the target).
    -- This is the only table step 50 reads.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_REL_S4_FINAL AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT t.*,
           t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')  AS rel_pkey,
           1 /* TIMELINE: VERSION_SEQ */                                       AS version_seq,
           1                                                                    AS hub_state_ind,
           'Member Relationship'                                                AS rel_type_code,
           'Member'                                                             AS hierarchy_code,
           'batchload'                                                          AS batch_user,
           'FSS'                                                                AS src_sys,
           :l_run_ts                                                            AS run_ts,
           :c_mapping                                                           AS mapping_name,
           'Relationship|Sex'                                                   AS attr_relationship,
           ex.EXCEPTION_CODE                                                    AS exc_code,
           ex.EXCEPTION_DESC                                                    AS exc_desc,
           ex.EXCEPTION_TYPE                                                    AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY t.mstr_ref_code IS NULL,
                                        t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')
                               ORDER BY t.RELN_DT_LAST_UPDATE DESC, t.ID_REGISTRATION) = 1
            AND xr.PKEY_SRC_OBJECT IS NULL)                                     AS uq_rel,
           ROW_NUMBER() OVER (PARTITION BY t.mstr_ref_code IS NULL, t.RELN_ID_CLIENT, t.ID_CLIENT,
                                       t.ID_REGISTRATION ORDER BY t.RELN_DT_LAST_UPDATE DESC) = 1 AS uq_rel_exc
      FROM WRK_FSS_REL_S3_TYPED t
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Relationship'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_REL WHERE VERSION_SEQ = 1) xr
             ON xr.PKEY_SRC_OBJECT = t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '');
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_REL_S4_FINAL;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'FINAL', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_REL_S4_FINAL', 'CREATED',
        'Final relationship rows: key, constants, exception details and insert-only guards. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 FINAL', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The two INSERTs below are the two branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final CTE to step 40.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 50a. Valid relationships -> C_S_FSS_PTY_RLE_REL
    INSERT INTO C_S_FSS_PTY_RLE_REL
           (REL_TP, VERSION_SEQ, HUB_STATE_IND, REL_TYPE_CODE, HIERARCHY_CODE, UPDATED_BY, LAST_UPDATE_DATE,
            PERIOD_START_DATE, PKEY_SRC_OBJECT, PTY_RLE_FK_1, PTY_RLE_FK_2, SRC_LAST_UPD_DT, CREATOR, SRC_ROWID,
            CREATE_DATE)
    SELECT mstr_ref_code, version_seq, hub_state_ind, rel_type_code, hierarchy_code, batch_user, run_ts,
           RELN_DT_CREATED, rel_pkey, rel_fk_1, rel_fk_2, RELN_DT_LAST_UPDATE, batch_user, rel_pkey,
           RELN_DT_LAST_UPDATE
      FROM WRK_FSS_REL_S4_FINAL
     WHERE mstr_ref_code IS NOT NULL AND uq_rel;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50b. Relationship exceptions -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME, PERIOD_START_DATE,
            EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE, SRC_SYS_ID_3, GENDER)
    SELECT src_sys, RELN_ID_CLIENT, ID_CLIENT, run_ts, mapping_name, attr_relationship, RELN_DT_CREATED,
           exc_type, exc_code, exc_desc, relation_cd, ID_REGISTRATION, out_gender_cd
      FROM WRK_FSS_REL_S4_FINAL
     WHERE mstr_ref_code IS NULL AND uq_rel_exc;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_FSS_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid relationships and untranslated-relationship exceptions. '
        || 'Count shown is the total rows inserted by both INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_FSS_Pty_Rle_Rel completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_FSS_Pty_Rle_Rel failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
