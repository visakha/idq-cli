-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads family-to-child relationships into the relationship table.
--   Every family row is read twice: once as family-to-child (code =
--   family code) and once as child-to-family (code = family code plus
--   the child's gender). A relationship whose code translates in the
--   code-value table loads; one whose code does not translate is only
--   logged as an exception.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> keyed
--   -> coded -> typed -> built -> final SELECT), one transaction, one
--   log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_REL_S10_SRC      family rows doubled (one row per
--                                     direction)
--   Step 20  WRK_ECI_REL_S20_KEYED    child / family party keys +
--                                     both parties must be active
--   Step 30  WRK_ECI_REL_S30_TYPED    relationship code built (child
--                                     gender for the reverse direction)
--                                     and translated
--   Step 40  WRK_ECI_REL_S40_READY    relationship keys, exception
--                                     details and insert-only guards
--   Step 50  PUBLISH                targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_REL_S10_SRC, WRK_ECI_REL_S20_KEYED,
--   WRK_ECI_REL_S30_TYPED, WRK_ECI_REL_S40_READY. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Keys already present are skipped (uq_rel
--     guard).
--   * The relationship code must translate in LOOKUP_CODE_VALUE (code
--     types REL_TP / INVERSE_REL, source ECI); preserved as a direct
--     table lookup, not a helper, exactly as in the original.
--   * An untranslated relationship is not loaded, only logged. The
--     exception row writes the exception code returned by the
--     exception-catalogue lookup (NULL when 'Invalid_Relationship' is
--     not configured); preserved. Its key SRC_SYS_ID_3 ends in '|'
--     (the master code is NULL; IDQ concatenates NULL as ''); preserved.
--   * VERSION_SEQ is 1; PERIOD_START_DATE is family DATE_CREATED;
--     CREATE_DATE is DATE_MODIFIED (as IDQ links it); preserved.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Rel';
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
    DROP TABLE IF EXISTS WRK_ECI_REL_S10_SRC;
    DROP TABLE IF EXISTS WRK_ECI_REL_S20_KEYED;
    DROP TABLE IF EXISTS WRK_ECI_REL_S30_TYPED;
    DROP TABLE IF EXISTS WRK_ECI_REL_S40_READY;

    -- ---- Step 10: FAMILY ROWS, BOTH DIRECTIONS ----------------------------
    -- Purpose: every family row twice -- 'To Child' and 'From Child'.
    -- This is the original src CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_REL_S10_SRC AS
    SELECT d.RELATION_DIRECTION, f.ID_FAMILY, f.GENDER AS FAMILY_GENDER, f.ID_CHILD, f.FAMILY_CD,
           COALESCE(f.DATE_MODIFIED, f.DATE_CREATED) AS DATE_MODIFIED, f.DATE_CREATED
      FROM STG_ECI_D_FAMILY f
     CROSS JOIN (SELECT column1 AS RELATION_DIRECTION FROM VALUES ('From Child'), ('To Child')) d;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_REL_S10_SRC;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_BOTH_DIRECTIONS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_REL_S10_SRC', 'CREATED',
        'Family rows doubled, one row per relationship direction. Read by the keying step.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_BOTH_DIRECTIONS', :l_rows) || CHR(10);

    -- ---- Step 20: PARTY KEYS + BOTH PARTIES ACTIVE --------------------------
    -- Purpose: build the child and family party keys and keep only
    -- rows where NEITHER party has a deactivation status. This is the
    -- original keyed CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_REL_S20_KEYED AS
    SELECT s.*,
           LPAD(TO_VARCHAR(s.ID_CHILD), 10, '0')          AS child_pty_src_key,
           LPAD(TO_VARCHAR(s.ID_FAMILY), 10, '0') || 'F'  AS family_pty_src_key
      FROM WRK_ECI_REL_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = LPAD(TO_VARCHAR(s.ID_CHILD), 10, '0') AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = LPAD(TO_VARCHAR(s.ID_FAMILY), 10, '0') || 'F'
                          AND i.ROWID_SYSTEM = 'ECI' AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_REL_S20_KEYED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'KEYED_BOTH_ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_REL_S20_KEYED', 'CREATED',
        'Keyed rows where both the child and the family are active. Read by the coding step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 KEYED_BOTH_ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 30: RELATIONSHIP CODE + TRANSLATION -----------------------------
    -- Purpose: build the relationship code (family code alone for the
    -- family-to-child direction; family code plus child gender for the
    -- reverse direction) and translate it in the code-value table.
    -- Reads ONLY step 20. This is the original coded + typed CTEs.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_REL_S30_TYPED AS
    WITH
    coded AS (
        SELECT k.*,
               IFF(k.RELATION_DIRECTION = 'To Child', TO_VARCHAR(k.FAMILY_CD),
                   NVL(TO_VARCHAR(k.FAMILY_CD), '') || '|' || NVL(ch.GENDER, ''))     AS rel_family_cd
          FROM WRK_ECI_REL_S20_KEYED k
          LEFT JOIN (SELECT c.ID_CHILD, c.GENDER FROM STG_ECI_SN_CHILD c
                     QUALIFY ROW_NUMBER() OVER (PARTITION BY c.ID_CHILD ORDER BY c.GENDER) = 1) ch
                 ON ch.ID_CHILD = k.ID_CHILD
    )
    SELECT c.*, lk.MSTR_REF_CODE AS mstr_ref_code
      FROM coded c
      LEFT JOIN (SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                  WHERE l.CODE_TYPE IN ('REL_TP', 'INVERSE_REL') AND l.SRC_SYS = 'ECI'
                QUALIFY ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.CODE_TYPE DESC,
                                           l.MSTR_REF_CODE) = 1) lk
             ON lk.SRC_CODE_VALUE = c.rel_family_cd;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_REL_S30_TYPED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'CODED_TRANSLATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_REL_S30_TYPED', 'CREATED',
        'Relationship codes built and translated (NULL when the code does not translate). '
        || 'Read by the ready step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 CODED_TRANSLATED', :l_rows) || CHR(10);

    -- ---- Step 40: READY -- keys, exception details, guards ---------------------
    -- Purpose: build the two role keys and the relationship record key,
    -- resolve the exception details, and apply the insert-only guards.
    -- Reads ONLY step 30. This is the original built CTE plus the final
    -- SELECT (including the target-table guard join, which still sees
    -- the pre-run state because nothing has been published yet).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_REL_S40_READY AS
    WITH
    built AS (
        SELECT t.*,
               IFF(t.RELATION_DIRECTION = 'To Child', t.family_pty_src_key, t.child_pty_src_key) || '|Member'
                                                                                          AS rel_fk_1,
               IFF(t.RELATION_DIRECTION = 'To Child', t.child_pty_src_key, t.family_pty_src_key) || '|Member'
                                                                                          AS rel_fk_2,
               IFF(t.RELATION_DIRECTION = 'To Child', t.family_pty_src_key, t.child_pty_src_key) || '|Member|'
               || IFF(t.RELATION_DIRECTION = 'To Child', t.child_pty_src_key, t.family_pty_src_key) || '|Member|'
               || NVL(t.mstr_ref_code, '')                                               AS rel_src_key
          FROM WRK_ECI_REL_S30_TYPED t
    )
    SELECT b.*,
           1 /* TIMELINE: VERSION_SEQ */                  AS version_seq,
           1                                              AS hub_state_ind,
           'Member Relationship'                          AS rel_type_code,
           'Member'                                       AS hierarchy_code,
           'ECI'                                          AS src_sys,
           :l_run_ts                                      AS run_ts,
           :c_mapping                                     AS mapping_name,
           'FAMILY_CD'                                    AS attr_family_cd,
           ex.EXCEPTION_CODE                              AS exc_code,
           ex.EXCEPTION_DESC                              AS exc_desc,
           ex.EXCEPTION_TYPE                              AS exc_type,
           (ROW_NUMBER() OVER (PARTITION BY b.mstr_ref_code IS NULL, b.rel_src_key
                                   ORDER BY b.DATE_MODIFIED DESC, b.ID_FAMILY) = 1
            AND xr.PKEY_SRC_OBJECT IS NULL)               AS uq_rel,
           ROW_NUMBER() OVER (PARTITION BY b.mstr_ref_code IS NULL, b.ID_FAMILY, b.ID_CHILD, b.rel_src_key
                                  ORDER BY b.DATE_MODIFIED DESC) = 1 AS uq_rel_exc
      FROM built b
      LEFT JOIN (SELECT * FROM TABLE(fn_snow_helper40_common())) ex ON ex.EXCEPTION_CODE = 'Invalid_Relationship'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_REL WHERE VERSION_SEQ = 1) xr
             ON xr.PKEY_SRC_OBJECT = b.rel_src_key;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_REL_S40_READY;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'READY_TO_PUBLISH', 'COMPLETED', 'C_S_ECI_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_ECI_REL_S40_READY', 'CREATED',
        'Publish-ready relationships with keys, exception details and insert-only guards '
        || '(uq_rel, uq_rel_exc). Published in step 50.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The two INSERTs below are
    -- the two branches of the original INSERT ALL, in the same order,
    -- with the same column lists, values and WHERE conditions -- only
    -- the source changed, from the final SELECT to step 40. No
    -- TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    -- 50a. Valid relationships -> C_S_ECI_PTY_RLE_REL
    INSERT INTO C_S_ECI_PTY_RLE_REL
           (PTY_RLE_FK_1, PTY_RLE_FK_2, PKEY_SRC_OBJECT, VERSION_SEQ, SRC_ROWID, HUB_STATE_IND, REL_TYPE_CODE,
            HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
            PERIOD_START_DATE)
    SELECT rel_fk_1, rel_fk_2, rel_src_key, version_seq, rel_src_key, hub_state_ind, rel_type_code,
           hierarchy_code, mstr_ref_code, DATE_MODIFIED, run_ts, mapping_name, DATE_MODIFIED, mapping_name,
           DATE_CREATED
      FROM WRK_ECI_REL_S40_READY
     WHERE mstr_ref_code IS NOT NULL AND uq_rel;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 50b. Relationship exceptions -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME,
            PERIOD_START_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE)
    SELECT src_sys, ID_FAMILY, ID_CHILD, rel_src_key, run_ts, mapping_name, attr_family_cd, DATE_CREATED,
           exc_type, exc_code, exc_desc, rel_family_cd
      FROM WRK_ECI_REL_S40_READY
     WHERE mstr_ref_code IS NULL AND uq_rel_exc;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    l_rows := l_pub_rows;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'C_S_ECI_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid relationships and relationship exception rows. '
        || 'Count shown is rows inserted across all publish branches.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_ECI_Pty_Rle_Rel completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_ECI_Pty_Rle_Rel failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
