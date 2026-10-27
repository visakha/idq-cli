-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-27  TOA codes must translate through the TOA crosswalk, and
--          periods must be sane (BEGIN_DT <= END_DT).  A row failing
--          EITHER test is an exception; a row failing BOTH writes BOTH
--          exception rows (router semantics, not either/or).
--   BR-02  Every failing class goes to EXC_STG_BAD_REC_MEMB; the load
--          does not fail because of bad rows.
--   BR-10  Only valid members (STG_TRS_VALID_MEMBERS spine) get TOA rows.
--   BR-01  Insert-only staging load (see Parity notes: no truncate here).
--   Key = INDV_ID|Member|<TOA master code>|TIERS|<EDG_NUM>|<PROGRAM_CD>
--         |<MCI_CREATE_SEQ>.  Do not confuse this with the TOA catalogue
--         load (m_Tgt_C_S_TRS_Stg_TOA, BR-51), which stages the code
--         list itself.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement (three branches: Bad_Value ->
--   exception, inverted dates -> exception, Default -> TOA target), one
--   CTE chain (toa_src -> src -> keyed -> outer SELECT with the three
--   uniqueness flags and the exception lookups), one transaction, one
--   log line.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target row-class)
--   inside ONE transaction, so a publish either lands completely or
--   not at all.  Because the three branches are separate INSERTs, a
--   row failing both tests correctly writes both exception rows, and
--   a row failing either test correctly does not load -- exactly as
--   the INSERT ALL did.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_TOA_S10_RAW    TOA rows for valid members, latest
--                                   create per individual/EDG/program/seq
--   Step 20  WRK_TRS_TOA_S20_SRC    latest row only (VERSION_SEQ = 1)
--   Step 30  WRK_TRS_TOA_S30_KEYED  code translated, source decoded, keys
--                                   built, both failure flags set
--   Step 40  WRK_TRS_TOA_S40_RANKED exception text resolved, three
--                                   uniqueness flags computed
--   Step 50  PUBLISH                 C_S_TRS_PTY_RLE_TOA + exceptions,
--                                    in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_TOA_S10_RAW, WRK_TRS_TOA_S20_SRC, WRK_TRS_TOA_S30_KEYED,
--   WRK_TRS_TOA_S40_RANKED.  They live in the same schema as the targets
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
--     DELETE of the targets.  IDQ truncates C_S_TRS_PTY_RLE_TOA; the
--     Snowflake version instead skips keys already present (the uq_*
--     flags in step 40).  A re-run therefore inserts nothing twice,
--     but it also does not remove rows that IDQ would have truncated
--     away -- see the User Guide, "Parity gaps".
--   * The Bad_Value exception row writes the looked-up EXCEPTION_CODE
--     for 'Invalid_TOA', which is NULL when that code is not configured
--     in EXC_LOOKUP_CODE_VALUE -- preserved, not defaulted.  The date
--     exception row writes the computed code
--     'Period_Start_Date_>_Period_End_Date'.
--   * The original source carries only the MCI_EDG_INDV branch
--     (SRC_TBL = 'MCI_EDG_INDV', decoded to source 'TIERS'); the
--     LTSS_ELIG_PER / 'DADS' branch of the IDQ mapping is not present
--     in the Snowflake original, and the DECODE that would map it is
--     kept verbatim (it can never fire on this branch alone).
--   * VERSION_SEQ is the source ROW_NUMBER() kept only where it equals
--     1, i.e. always 1 in the published rows; PERIOD_START_DATE /
--     EFF_STRT_DT = BEGIN_DT, PERIOD_END_DATE / EFF_END_DT = END_DT;
--     PERIOD_REFERENCE_TIME is NULL (unfed port).
--   * ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR and HUB_STATE_IND
--     are NULL (unfed ports), as in the original.
--
-- SIGNATURE
--   The original procedure took no parameters, so there is nothing to
--   preserve in order.  One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_TOA';
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
    DROP TABLE IF EXISTS WRK_TRS_TOA_S10_RAW;
    DROP TABLE IF EXISTS WRK_TRS_TOA_S20_SRC;
    DROP TABLE IF EXISTS WRK_TRS_TOA_S30_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_TOA_S40_RANKED;

    -- ---- Step 10: TOA SOURCE ROWS, RANKED (BR-27/10) ---------------------
    -- Purpose: TOA rows for valid members only (spine join on
    -- TO_VARCHAR(INDV_ID) = PTY_PK), with a code present and a
    -- conversion indicator of null or 'C', ranked by latest CREATE_DT
    -- within each individual / EDG / program / MCI-sequence group.
    -- VERSION_SEQ here is that rank; step 20 keeps rank 1.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_TOA_S10_RAW AS
    SELECT TO_VARCHAR(toa.INDV_ID) AS INDV_ID, toa.TYPE_OF_ASSISTANCE_CD, toa.ELIG_EFF_BEGIN_DT AS BEGIN_DT,
           toa.ELIG_EFF_END_DT AS END_DT, 'MCI_EDG_INDV' AS SRC_TBL,
           ROW_NUMBER() OVER (PARTITION BY TO_VARCHAR(toa.INDV_ID) || '|' || NVL(TO_VARCHAR(toa.EDG_NUM), '')
                                           || '|' || NVL(TO_VARCHAR(toa.PROGRAM_CD), '') || '|'
                                           || NVL(TO_VARCHAR(toa.MCI_CREATE_SEQ), '')
                              ORDER BY toa.CREATE_DT DESC) AS VERSION_SEQ,
           TO_VARCHAR(toa.INDV_ID) AS PTY_PK, toa.EDG_NUM, toa.CASE_NUM, toa.MCI_CREATE_SEQ, toa.PROGRAM_CD,
           toa.PART_STATUS_CD, toa.SYSTEM_CD, toa.CONVERT_DT, toa.CREATE_DT
      FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA toa
      JOIN STG_TRS_VALID_MEMBERS vm ON TO_VARCHAR(toa.INDV_ID) = vm.PTY_PK
     WHERE toa.TYPE_OF_ASSISTANCE_CD IS NOT NULL
       AND (toa.CONVERSION_IND IS NULL OR toa.CONVERSION_IND = 'C');
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_TOA_S10_RAW;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'TOA_SRC_RANKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_TOA_S10_RAW', 'CREATED',
        'TOA rows for valid members only, ranked by latest create per group. '
        || 'Read by the latest-only step (BR-27/10).',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 TOA_SRC_RANKED', :l_rows) || CHR(10);

    -- ---- Step 20: LATEST ROW ONLY ----------------------------------------
    -- Purpose: keep only VERSION_SEQ = 1 -- the latest create per
    -- group.  Everything downstream sees one row per TOA segment.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_TOA_S20_SRC AS
    SELECT * FROM WRK_TRS_TOA_S10_RAW WHERE VERSION_SEQ = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_TOA_S20_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'TOA_LATEST', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_TOA_S20_SRC', 'CREATED',
        'Latest TOA row per segment only (VERSION_SEQ = 1). Read by the translation/keying step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 TOA_LATEST', :l_rows) || CHR(10);

    -- ---- Step 30: TRANSLATE + KEY + FAILURE FLAGS (BR-27) ----------------
    -- Purpose: translate the assistance code through LOOKUP_CODE_VALUE
    -- (CODE_TYPE = 'TOA', SRC_SYS = 'TRS', first master code per source
    -- value), decode the source (MCI_EDG_INDV -> 'TIERS'), build the
    -- segment key, the party-role key and the staging key, and set the
    -- two failure flags: grp_bad_value (code did not translate) and
    -- grp_dates (BEGIN_DT > END_DT, null-safe).  A row can have both
    -- flags set; that is handled in publish, not hidden here.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_TOA_S30_KEYED AS
    SELECT s.*,
           lk.MSTR_REF_CODE AS toa_cd,
           DECODE(s.SRC_TBL, 'LTSS_ELIG_PER', 'DADS', 'MCI_EDG_INDV', 'TIERS') AS toa_source,
           NVL(TO_VARCHAR(s.EDG_NUM), '') || '|' || NVL(TO_VARCHAR(s.PROGRAM_CD), '') || '|'
           || NVL(TO_VARCHAR(s.MCI_CREATE_SEQ), '') AS sgmnt_key,
           s.INDV_ID || '|Member' AS pty_rle_fk,
           s.INDV_ID || '|Member|' || NVL(lk.MSTR_REF_CODE, '') || '|'
           || NVL(DECODE(s.SRC_TBL, 'LTSS_ELIG_PER', 'DADS', 'MCI_EDG_INDV', 'TIERS'), '') || '|'
           || NVL(TO_VARCHAR(s.EDG_NUM), '') || '|' || NVL(TO_VARCHAR(s.PROGRAM_CD), '') || '|'
           || NVL(TO_VARCHAR(s.MCI_CREATE_SEQ), '') AS pkey_src_object,
           lk.MSTR_REF_CODE IS NULL AS grp_bad_value,
           NVL(s.BEGIN_DT > s.END_DT, FALSE) AS grp_dates
      FROM WRK_TRS_TOA_S20_SRC s
      LEFT JOIN (SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE FROM LOOKUP_CODE_VALUE l
                  WHERE l.CODE_TYPE = 'TOA' AND l.SRC_SYS = 'TRS'
                QUALIFY ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.MSTR_REF_CODE) = 1) lk
             ON lk.SRC_CODE_VALUE = s.TYPE_OF_ASSISTANCE_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_TOA_S30_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'TOA_KEYED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_TOA_S30_KEYED', 'CREATED',
        'Rows with the TOA code translated, keys built, and both failure flags set '
        || '(untranslated code, inverted dates). Read by the ranking step (BR-27).',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 TOA_KEYED', :l_rows) || CHR(10);

    -- ---- Step 40: EXCEPTION TEXT + UNIQUENESS FLAGS (BR-27/02) -----------
    -- Purpose: the publish-ready rows.  Exception description/type
    -- resolved for 'Invalid_TOA' and for
    -- 'Period_Start_Date_>_Period_End_Date'; uq_toa = first row per
    -- key (among rows failing either test) whose key is not already in
    -- the TOA target; uq_exc_toa = first Bad_Value row per individual /
    -- EDG / sequence; uq_exc_dates = first inverted-date row per key /
    -- role.  The existing-key guard reads the live target here, at
    -- step time, as in the original -- a target row inserted between
    -- step 40 and publish would not be re-checked (see the User Guide
    -- on publish timing).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_TOA_S40_RANKED AS
    WITH lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT k.*,
           'TRS' AS src_sys,
           :l_run_ts AS run_ts,
           :c_mapping AS mapping_name,
           'Type of Assistance' AS attr_toa,
           'Effective Date' AS attr_dates,
           xt.EXCEPTION_CODE AS toa_exc_code,
           xt.EXCEPTION_DESC AS toa_exc_desc,
           xt.EXCEPTION_TYPE AS toa_exc_type,
           'Period_Start_Date_>_Period_End_Date' AS date_exc_code,
           xd.EXCEPTION_DESC AS date_exc_desc,
           xd.EXCEPTION_TYPE AS date_exc_type,
           (ROW_NUMBER() OVER (PARTITION BY k.grp_bad_value OR k.grp_dates, k.pkey_src_object
                                   ORDER BY k.CREATE_DT DESC) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL) AS uq_toa,
           ROW_NUMBER() OVER (PARTITION BY k.grp_bad_value, k.INDV_ID, k.EDG_NUM, k.MCI_CREATE_SEQ
                                  ORDER BY k.CREATE_DT DESC) = 1 AS uq_exc_toa,
           ROW_NUMBER() OVER (PARTITION BY k.grp_dates, k.pkey_src_object, k.pty_rle_fk
                                  ORDER BY k.CREATE_DT DESC) = 1 AS uq_exc_dates
      FROM WRK_TRS_TOA_S30_KEYED k
      LEFT JOIN lkp_exc xt ON xt.EXCEPTION_CODE = 'Invalid_TOA'
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_TOA WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = k.pkey_src_object;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_TOA_S40_RANKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'TOA_RANKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_TOA_S40_RANKED', 'CREATED',
        'Publish-ready rows: exception text resolved, uq_toa / uq_exc_toa / uq_exc_dates computed. '
        || 'Read by publish (BR-27/02).',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 TOA_RANKED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all three row-classes ------
    -- This is the ONLY step that writes to final targets.  The three
    -- INSERTs below are the three branches of the original INSERT ALL,
    -- in the same order, with the same column lists, values and WHERE
    -- conditions -- only the source changed, from the outer SELECT to
    -- step 40.  Note the router semantics, preserved exactly: a row
    -- with BOTH flags writes BOTH exception rows (50a and 50b), and a
    -- row with either flag does NOT load (50c requires neither flag).
    -- If any INSERT fails, the whole publish rolls back, the
    -- step-10..40 checkpoints (already committed) survive, the work
    -- tables survive, and the run must be restarted from the beginning (step 5 cleanup, then step 10) 50.
    BEGIN TRANSACTION;
    -- 50a. Bad_Value -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE, ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, run_ts, attr_toa, mapping_name, BEGIN_DT, END_DT, toa_exc_code, toa_exc_desc,
           toa_exc_type, TYPE_OF_ASSISTANCE_CD, INDV_ID, EDG_NUM, MCI_CREATE_SEQ
      FROM WRK_TRS_TOA_S40_RANKED
     WHERE grp_bad_value AND uq_exc_toa;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 50b. Inverted dates -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
            PERIOD_END_DATE, SRC_SYS, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
    SELECT pkey_src_object, pty_rle_fk, mapping_name, run_ts, attr_dates, BEGIN_DT, END_DT, src_sys,
           date_exc_desc, date_exc_type, date_exc_code
      FROM WRK_TRS_TOA_S40_RANKED
     WHERE grp_dates AND uq_exc_dates;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 50c. Default (neither failure) -> C_S_TRS_PTY_RLE_TOA
    INSERT INTO C_S_TRS_PTY_RLE_TOA
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE,
            CREATOR, SRC_ROWID, HUB_STATE_IND, TOA_SOURCE, TOA_FK, EFF_STRT_DT, EFF_END_DT, PTY_RLE_FK, EDG_NUM,
            CASE_NUM, SGMNT_KEY, CNVRT_DT, CNVRT_SYS_CD, INDV_ID, PRTCPNT_STS_CD, SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, BEGIN_DT, END_DT, VERSION_SEQ, NULL, run_ts, NULL,
           CREATE_DT, NULL, pkey_src_object, NULL, toa_source, toa_cd, BEGIN_DT, END_DT, pty_rle_fk, EDG_NUM,
           CASE_NUM, sgmnt_key, CONVERT_DT, SYSTEM_CD, PTY_PK, PART_STATUS_CD, CREATE_DT
      FROM WRK_TRS_TOA_S40_RANKED
     WHERE NOT grp_bad_value AND NOT grp_dates AND uq_toa;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED', 'C_S_TRS_PTY_RLE_TOA, EXC_STG_BAD_REC_MEMB', :l_pub_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid TOA segments and both exception classes. '
        || 'A row failing both tests wrote both exception rows (BR-27). '
        || 'Count shown is rows inserted across both targets.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (TOA + exceptions)', :l_pub_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_TOA completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_TOA failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
