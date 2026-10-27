-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Alt_Id, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-22  One alt-ID row per person per ID; longest and latest SSN wins.
--   BR-23  Only TIERS-validated SSNs are carried as valid.
--   BR-24  Member ID creates two alt-ID rows (member ID is also fed as
--          the Medicaid ID; see the parity note below).
--   BR-25  Loaded alt-ID rows carry STS_CD = 'Issued'.
--   BR-02  Invalid Medicaid / member IDs are logged, not loaded; an
--          invalid SSN is blanked and dropped, never logged.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (all_indv ->
--   de_dup_indv -> src -> with_ssn -> normalized -> routed -> final),
--   one transaction, one log line at the end.  If it failed, nothing
--   told you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE transaction,
--   so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_ALT_S1_SRC       one valid-member key per person,
--                                     longest + latest SSN only (BR-22)
--   Step 20  WRK_TRS_ALT_S2_SSN       keep only the SSA-validated SSN (BR-23)
--   Step 30  WRK_TRS_ALT_S3_NORM      one row per alternate ID, with its
--                                     validation exception code (BR-22/24)
--   Step 40  WRK_TRS_ALT_S4_ROUTED    alt-ID type translated, null IDs
--                                     dropped, valid / exception rows
--                                     flagged, insert-only guards set
--   Step 50  PUBLISH                  targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_ALT_S1_SRC, WRK_TRS_ALT_S2_SSN, WRK_TRS_ALT_S3_NORM,
--   WRK_TRS_ALT_S4_ROUTED.  They live in the same schema as the targets
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
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_ALT_ID; the
--     Snowflake version instead skips keys already present (uq_alt_id).
--     A re-run therefore inserts nothing twice, but it also does not
--     remove rows that IDQ would have truncated away.
--   * The stored source filter INDV_ID = 504937068 is NOT applied here,
--     exactly as in the original Snowflake code (it was not part of the
--     custom query).  Confirm in the live IDQ mapping whether it should
--     be (BR notes, Verify item 1).
--   * VERSION_SEQ is hard-coded to 1 (TIMELINE: the rank is commented out
--     in IDQ), so the rank filter keeps EVERY row.  PERIOD_END_DATE,
--     PERIOD_REFERENCE_TIME and TIMELINE_ACTION are NULL (unfed ports).
--   * ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR and HUB_STATE_IND
--     are NULL (unfed ports), as in the original.
--   * An invalid SSN is blanked by the normalizer and then dropped by
--     the null-ID filter, never logged -- preserved, not changed.
--   * When LKP_ALT_ID_LBL does not find a type, the key has an empty
--     type part, so the Medicaid and member rows of one person (same
--     value) get the SAME key: IDQ gets the second row rejected, and
--     Snowflake writes the first row per key only (uq_alt_id).
--   * The member ID is fed as BOTH the member ID ('007') and the
--     Medicaid ID ('002') by the normalizer call (BR-24), so a
--     10-character member ID fails the 9-character Medicaid rule and
--     is logged as an exception on its Medicaid row while its member
--     row loads.  That is the original behaviour, preserved.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id';
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
    DROP TABLE IF EXISTS WRK_TRS_ALT_S1_SRC;
    DROP TABLE IF EXISTS WRK_TRS_ALT_S2_SSN;
    DROP TABLE IF EXISTS WRK_TRS_ALT_S3_NORM;
    DROP TABLE IF EXISTS WRK_TRS_ALT_S4_ROUTED;

    -- ---- Step 10: SOURCE + DE-DUP (BR-22) --------------------------------
    -- Purpose: one row per valid-member key, keeping the longest and
    -- latest SSN when a key has more than one.  MCI individuals, DC
    -- individuals and merged/split records (type_cd = 'ME') are unioned,
    -- joined to STG_TRS_VALID_MEMBERS, ranked by SSN length then create
    -- date, and only rank 1 is kept.  Every later step reads this table,
    -- never the raw sources again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ALT_S1_SRC AS
    WITH
    all_indv AS (
        SELECT DISTINCT TO_VARCHAR(mci_indv.indv_id) AS pty_pkey, mci_indv.indv_id AS member_id,
               mci_indv.create_dt, mci_indv.ssn, '1' AS cv_ind
          FROM STG_TRS_D_CV_DC_MCI_INDV mci_indv
        UNION ALL
        SELECT DISTINCT TO_VARCHAR(indv.indv_id) || '|DC_INDV', indv.indv_id, indv.create_dt, indv.ssn, NULL
          FROM STG_TRS_D_DC_INDV indv
        UNION ALL
        SELECT DISTINCT TO_VARCHAR(mrg.old_indv_id), mrg.indv_id, mrg.create_dt, NULL, NULL
          FROM STG_TRS_D_CV_DC_MRG_SPRT_INDV mrg
         WHERE mrg.type_cd = 'ME'
    ),
    de_dup_indv AS (
        SELECT a.pty_pkey, TO_VARCHAR(a.member_id) AS member_id, a.create_dt AS start_dt, a.ssn, a.cv_ind,
               ROW_NUMBER() OVER (PARTITION BY a.pty_pkey
                                  ORDER BY LENGTH(TO_VARCHAR(a.ssn)) DESC NULLS LAST, a.create_dt DESC) AS key_rn
          FROM all_indv a
          JOIN STG_TRS_VALID_MEMBERS vm ON a.pty_pkey = vm.pty_pk
    )
    SELECT pty_pkey AS PTY_PKEY, member_id AS MEMBER_ID, start_dt AS START_DT, ssn AS SSN, cv_ind AS CV_IND
      FROM de_dup_indv
     WHERE key_rn = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ALT_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_DEDUP', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ALT_S1_SRC', 'CREATED',
        'One valid-member key per person, longest + latest SSN only (BR-22). '
        || 'Read by the SSN-validation step; never re-read the raw sources after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_DEDUP', :l_rows) || CHR(10);

    -- ---- Step 20: SSA-VALIDATED SSN ONLY (BR-23) --------------------------
    -- Purpose: attach the SSN only when STG_TRS_H_DC_INDV has it
    -- SSA-validated for the individual.  An SSN that was never validated
    -- in TIERS comes back NULL here, so the normalizer in step 30 can
    -- only ever emit a validated SSN.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ALT_S2_SSN AS
    SELECT s.*, v.SSN AS valid_ssn
      FROM WRK_TRS_ALT_S1_SRC s
      LEFT JOIN (SELECT DISTINCT INDV_ID, SSN FROM STG_TRS_H_DC_INDV
                  WHERE SSA_VALIDATION_SW = 'Y' AND SSN > 0) v
             ON v.INDV_ID = fn_snow_helper04_common(s.MEMBER_ID, 0) AND v.SSN = s.SSN
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.PTY_PKEY ORDER BY v.SSN) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ALT_S2_SSN;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'SSN_VALIDATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ALT_S2_SSN', 'CREATED',
        'Source keys with only the SSA-validated SSN attached (BR-23). '
        || 'Read by the normalizer step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 SSN_VALIDATED', :l_rows) || CHR(10);

    -- ---- Step 30: NORMALIZE -- one row per alternate ID (BR-22/24) -------
    -- Purpose: pivot each person's IDs into rows (Medicaid '002', SSN
    -- '004', member '007', NIS client '009') with the validation
    -- exception code for each.  The member ID is fed as both the member
    -- ID and the Medicaid ID, and the NIS client ID is NULL, exactly as
    -- in the original call.  An invalid SSN is blanked here and dropped
    -- by the null-ID filter in step 40, never logged.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ALT_S3_NORM AS
    SELECT n.*
      FROM WRK_TRS_ALT_S2_SSN w,
           TABLE(fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id(w.PTY_PKEY, w.START_DT, 'TRS', w.MEMBER_ID,
                                                               w.valid_ssn, w.MEMBER_ID, NULL, w.CV_IND)) n;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ALT_S3_NORM;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'NORMALIZED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ALT_S3_NORM', 'CREATED',
        'One row per alternate ID (Medicaid, SSN, member, NIS client) with its validation exception code (BR-22/24). '
        || 'Read by the router step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 NORMALIZED', :l_rows) || CHR(10);

    -- ---- Step 40: ROUTE -- translate type, drop nulls, flag rows ---------
    -- Purpose: translate the alt-ID type through LOOKUP_CODE_VALUE
    -- (ALT_ID_TP), resolve the exception description, drop rows with a
    -- null or blank ID value, and set the two flags the publish step
    -- needs: is_valid (no exception code) and the insert-only guards
    -- uq_alt_id (first row per alt-ID key, key not already in the
    -- target) and uq_exc (first row per exception key in this run).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ALT_S4_ROUTED AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_lcv AS (SELECT * FROM TABLE(fn_snow_helper45_common())),
    routed AS (
        SELECT n.PKEY_SRC_OBJECT_PTY AS pkey_src_object_pty, n.PERIOD_START_DATE AS period_start_date,
               n.ALT_ID_VAL AS alt_id_val, lb.MSTR_REF_CODE AS alt_id_typ, lb.MSTR_REF_LABEL AS alt_id_label,
               n.DQ_EXCP_CD AS dq_excp_cd, xd.EXCEPTION_DESC AS dq_excp, n.SRC_SYS AS src_sys, n.CV_IND AS cv_ind,
               NVL(n.PKEY_SRC_OBJECT_PTY, '') || '|Member|' || NVL(lb.MSTR_REF_CODE, '') || '|' || n.ALT_ID_VAL
                                                                                     AS pkey_src_object_alt_id,
               NVL(n.PKEY_SRC_OBJECT_PTY, '') || '|Member'                           AS pty_rle_fk,
               /* VALIDATION */ fn_snow_helper03_common(n.DQ_EXCP_CD)                AS is_valid
          FROM WRK_TRS_ALT_S3_NORM n
          LEFT JOIN lkp_lcv lb ON lb.CODE_TYPE = 'ALT_ID_TP' AND lb.MSTR_REF_CODE = n.ALT_ID_TYP
                              AND lb.SRC_SYS = n.SRC_SYS
          LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = n.DQ_EXCP_CD
         /* BAD DATA: FLTR_Remove_Null_Alt_IDs: NOT ISNULL(ALT_ID_VAL) AND RTRIM(ALT_ID_VAL) <> '' */
         WHERE n.ALT_ID_VAL IS NOT NULL AND RTRIM(n.ALT_ID_VAL) <> ''
    )
    SELECT r.*,
           1 /* TIMELINE: exp_Rank.VERSION_SEQ hard-coded */                  AS version_seq,
           'Issued'                                                            AS sts_cd,
           'Bad Value'                                                         AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.is_valid, r.pkey_src_object_alt_id
                                   ORDER BY r.alt_id_typ NULLS LAST, r.period_start_date DESC) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                                    AS uq_alt_id,
           ROW_NUMBER() OVER (PARTITION BY r.is_valid, r.pkey_src_object_pty, r.dq_excp_cd
                                  ORDER BY r.alt_id_typ NULLS LAST) = 1        AS uq_exc
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = r.pkey_src_object_alt_id;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ALT_S4_ROUTED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'ROUTED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ALT_S4_ROUTED', 'CREATED',
        'Routed alt IDs: type translated, null IDs dropped, valid / exception flags and insert-only guards set. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 ROUTED', :l_rows) || CHR(10);

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
    -- 50a. Valid alt IDs -> C_S_TRS_PTY_RLE_ALT_ID
    INSERT INTO C_S_TRS_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, SRC_ROWID, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, ALT_ID_TP, ALT_ID_VAL,
            STS_CD, ALT_ID_TP_FLTR, CV_IND, PTY_RLE_FK, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
            PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE, CREATOR,
            HUB_STATE_IND, SRC_LAST_UPD_DT)
    SELECT pkey_src_object_alt_id, pkey_src_object_alt_id, period_start_date, version_seq, :l_run_ts,
           alt_id_typ, alt_id_val, sts_cd, alt_id_typ, cv_ind, pty_rle_fk, NULL, NULL, NULL, NULL, NULL,
           NULL, NULL, NULL, period_start_date, NULL, NULL, period_start_date
      FROM WRK_TRS_ALT_S4_ROUTED
     WHERE is_valid AND uq_alt_id;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50b. Invalid alt IDs -> EXC_STG_BAD_REC_MEMB (inside the IDQ mapplet)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (MAPPING_NAME, SRC_SYS, RUN_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, EXCEPTION_DESC, EXCEPTION_CODE,
            EXCEPTION_TYPE, SRC_SYS_ID_1)
    SELECT :c_mapping, src_sys, :l_run_ts, alt_id_val, alt_id_label, dq_excp, dq_excp_cd, exc_type,
           pkey_src_object_pty
      FROM WRK_TRS_ALT_S4_ROUTED
     WHERE NOT is_valid AND uq_exc;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_TRS_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid alt IDs and invalid-ID exceptions. '
        || 'Count shown is the total rows inserted by both INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
