-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, workflow
-- wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-28  Only DQ-clean contact points load; phones and emails that
--          fail validation go to EXC_STG_BAD_REC_MEMB, not to staging.
--   BR-29  Blank emails are dropped, not exceptioned.
--   BR-30  Phone numbers should be valid US numbers (area-code and
--          rule checks); directory / emergency / toll-free numbers are
--          rejected by the phone rule.
--   BR-02  Exceptions never fail the load; they accumulate for review.
--   BR-06  Duplicate phones and emails are consolidated before load, so
--          the MDM receives one record per key/timeline.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> slots ->
--   phones_checked -> phones -> phn_versions, plus emails ->
--   emails_checked -> eaddr_versions, all unioned into all_kinds with a
--   final SELECT), one transaction, one log line at the end.  If it
--   failed, nothing told you which logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The original all_kinds UNION is NOT recreated as a work
--   table: the phone and email branches stay separate, and the publish
--   step reads each branch directly, with the original WHEN conditions
--   as WHERE clauses (the final SELECT's derived columns -- exception
--   phone splits, exception attribute, e-mail constants, uq_tgt and
--   uq_exc -- are computed in the branch work tables or in the publish
--   INSERTs themselves, exactly as the original final SELECT did).
--   The final publish is the original INSERT ALL branches, written as
--   separate INSERT statements (one per target) inside ONE transaction,
--   so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_PHN_S1_SRC        case delta, valid members only
--   Step 20  WRK_TRS_PHN_S2_SLOTS      one row per phone slot (main /
--                                      work / other) per case
--   Step 30  WRK_TRS_PHN_S3_CHECKED    phones standardised + rule-checked
--                                      against the area-code reference
--   Step 40  WRK_TRS_PHN_S4_PHONES     phones with usage-type translation
--                                      + exception description, null
--                                      numbers dropped, exception
--                                      first-row flag set
--   Step 50  WRK_TRS_PHN_S5_VERSIONS   valid phones only, consolidated:
--                                      distinct, versioned, last row
--                                      per key wins (rn = 1)
--            (branch: step 50 reads step 40, the phone branch only)
--   Step 60  WRK_TRS_PHN_S6_EMAILS     emails, blank-dropped and
--                                      validated, with exception
--                                      description and first-row flag
--            (branch: step 60 reads step 10, NOT step 50 -- the email
--             branch is independent of the phone branch)
--   Step 70  WRK_TRS_PHN_S7_VERSIONS   valid emails only, consolidated:
--                                      distinct, versioned, last row
--                                      per key wins (rn = 1)
--            (branch: step 70 reads step 60, the email branch only)
--   Step 80  PUBLISH                   targets, in one transaction
--                                      (reads steps 40, 50, 60, 70)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_PHN_S1_SRC, WRK_TRS_PHN_S2_SLOTS, WRK_TRS_PHN_S3_CHECKED,
--   WRK_TRS_PHN_S4_PHONES, WRK_TRS_PHN_S5_VERSIONS, WRK_TRS_PHN_S6_EMAILS,
--   WRK_TRS_PHN_S7_VERSIONS.  They live in the same schema as the targets
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
--     DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_PHN and
--     C_S_TRS_PTY_RLE_EADDR; the Snowflake version instead skips keys
--     already present (uq_tgt).  A re-run therefore inserts nothing
--     twice, but it also does not remove rows that IDQ would have
--     truncated away.
--   * The stored source filter rownum < 100000 is NOT applied here,
--     exactly as in the original Snowflake code (it was not part of the
--     custom query).  Confirm whether it should be (BR notes, Verify
--     item 2).
--   * Inside the phone normalizer, the three rule instances get ONLY
--     the phone: their SRC_SYS and USG_TP inputs are not linked, so the
--     TRS / main-number toll-free check of the rule never runs here.
--   * The work phone is fed as "number extension"; the rule removes
--     the space and its string(10) port keeps the first ten characters,
--     so the extension is dropped and the number itself is validated
--     and written.  Preserved.
--   * The exception work-phone split in the original final SELECT
--     compares usg_tp to 'Work', while the phone branch's usg_tp values
--     are '001' / '002' / '003', so exc_work_phone is always NULL in
--     the original -- preserved, not "corrected" to a pref_lvl test.
--   * Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY,
--     CREATOR, HUB_STATE_IND, and USG_TP on the e-mail target.
--   * Email consolidation: the version sequence is the COUNT of
--     distinct versions of the key, and the aggregator keeps the LAST
--     row of the key, so VERSION_SEQ = number of distinct versions.
--     PERIOD_END_DATE is NULL (its port is not fed).
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
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
    DROP TABLE IF EXISTS WRK_TRS_PHN_S1_SRC;
    DROP TABLE IF EXISTS WRK_TRS_PHN_S2_SLOTS;
    DROP TABLE IF EXISTS WRK_TRS_PHN_S3_CHECKED;
    DROP TABLE IF EXISTS WRK_TRS_PHN_S4_PHONES;
    DROP TABLE IF EXISTS WRK_TRS_PHN_S5_VERSIONS;
    DROP TABLE IF EXISTS WRK_TRS_PHN_S6_EMAILS;
    DROP TABLE IF EXISTS WRK_TRS_PHN_S7_VERSIONS;

    -- ---- Step 10: SOURCE -- case delta, valid members only ---------------
    -- Purpose: the case/individual delta for people who are valid
    -- members today, with all three phone numbers and the e-mail.
    -- This is the single source both the phone branch (steps 20-50)
    -- and the e-mail branch (steps 60-70) read from.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S1_SRC AS
    SELECT DISTINCT I.INDV_ID, C.CASE_NUM, C.CREATE_DT, C.WORK_PH_NUM, C.OTHER_PH_NUM, C.EMAIL, C.PH_NUM,
           C.OFFICE_NUM, C.WORK_PH_NUM_EXT, TO_VARCHAR(I.INDV_ID) AS PTY_PK
      FROM STG_TRS_D_DC_CASES C
      JOIN STG_TRS_DC_CASE_INDV I ON C.CASE_NUM = I.CASE_NUM
      JOIN STG_TRS_VALID_MEMBERS VM ON TO_VARCHAR(I.INDV_ID) = VM.PTY_PK;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_CASE_DELTA', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S1_SRC', 'CREATED',
        'Case delta for valid members only, with phones and e-mail. '
        || 'Read by the phone-slot step and the e-mail step; never re-read the raw sources after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_CASE_DELTA', :l_rows) || CHR(10);

    -- ---- Step 20: PHONE SLOTS -- one row per phone -----------------------
    -- Purpose: unpivot each case row into its three phone slots --
    -- main (001, Primary), work (002, Secondary, number + extension),
    -- other (003, Tertiary) -- so each phone can be validated on its own.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S2_SLOTS AS
    SELECT n.*
      FROM WRK_TRS_PHN_S1_SRC s,
           TABLE(fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr(
                 s.CREATE_DT, s.PTY_PK, 'TRS', TO_VARCHAR(s.CASE_NUM),
                 '001', 'Telephone', s.PH_NUM,
                 '002', 'Telephone', IFF(s.WORK_PH_NUM IS NULL, NULL,
                                         RTRIM(s.WORK_PH_NUM || ' ' || NVL(s.WORK_PH_NUM_EXT, ''))),
                 '003', 'Telephone', s.OTHER_PH_NUM)) n;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S2_SLOTS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'PHONE_SLOTS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S2_SLOTS', 'CREATED',
        'One row per phone slot (main / work / other) per case. Read by the phone rule-check step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 PHONE_SLOTS', :l_rows) || CHR(10);

    -- ---- Step 30: PHONE RULE CHECK (BR-30) -------------------------------
    -- Purpose: standardise each phone number and run the phone rule
    -- against the area-code reference, producing the DQ exception code
    -- (NULL = clean).  Only the phone is linked into the rule; SRC_SYS
    -- and USG_TP are NULL, as in the original.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S3_CHECKED AS
    WITH
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common()))
    SELECT sl.*,
           fn_snow_helper23_common(sl.PHN_NUM_IN)                                          AS phn_num,
           /* VALIDATION */ fn_snow_helper24_common(fn_snow_helper23_common(sl.PHN_NUM_IN), NULL, NULL,
                                                    ar.NPA_ID, ar.SERVICE)                 AS dq_exception_code
      FROM WRK_TRS_PHN_S2_SLOTS sl
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(fn_snow_helper23_common(sl.PHN_NUM_IN), 1, 3);
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S3_CHECKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'PHONES_CHECKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S3_CHECKED', 'CREATED',
        'Phones standardised and rule-checked against the area-code reference; DQ exception code NULL = clean (BR-30). '
        || 'Read by the phone-translation step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 PHONES_CHECKED', :l_rows) || CHR(10);

    -- ---- Step 40: PHONES -- translate, describe, drop nulls --------------
    -- Purpose: drop null phone numbers, translate the usage type
    -- through LOOKUP_CODE_VALUE (PHN_USG_TP), resolve the exception
    -- description, build the party-role key and the phone staging key,
    -- and set the exception first-row flag (uq_exc) exactly as the
    -- original final SELECT did for phone-exception rows.  Both the
    -- valid-phone branch (step 50) and the phone-exception publish
    -- branch read this table.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S4_PHONES AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_lcv AS (SELECT * FROM TABLE(fn_snow_helper45_common())),
    phones AS (
        SELECT p.PERIOD_START_DATE AS period_start_date, p.PTY_FK AS pty_fk, p.PREF_LVL AS pref_lvl,
               p.USG_TP AS usg_tp, p.PHN_TP AS phn_tp, p.phn_num, p.SRC_SYS AS src_sys_in,
               p.CASE_NUMBER AS case_number, p.dq_exception_code, xp.EXCEPTION_DESC AS dq_exception,
               NVL(p.PTY_FK, '') || '|Member'                                                 AS pty_rle_fk,
               NVL(p.PTY_FK, '') || '|Member|' || NVL(p.PHN_TP, '') || '|' || NVL(u.MSTR_REF_CODE, '') || '|'
               || p.phn_num                                                                   AS pkey_src_object
          FROM WRK_TRS_PHN_S3_CHECKED p
          LEFT JOIN lkp_lcv u ON u.CODE_TYPE = 'PHN_USG_TP' AND u.MSTR_REF_CODE = p.USG_TP AND u.SRC_SYS = p.SRC_SYS
          LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = p.dq_exception_code
         WHERE p.phn_num IS NOT NULL
    )
    SELECT ph.*,
           ROW_NUMBER() OVER (PARTITION BY ph.pty_fk, ph.case_number, ph.usg_tp, 'Bad Value', ph.dq_exception_code
                                  ORDER BY ph.period_start_date DESC) = 1                       AS uq_exc
      FROM phones ph;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S4_PHONES;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'PHONES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S4_PHONES', 'CREATED',
        'Phones with usage-type translation, exception description and staging keys; null numbers dropped. '
        || 'Read by the phone-consolidation step and by the phone-exception publish branch.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 PHONES', :l_rows) || CHR(10);

    -- ---- Step 50: PHONE CONSOLIDATION (BR-06) ----------------------------
    -- Purpose: valid phones only, distinct, with a version sequence
    -- equal to the count of distinct versions of the key, and rn = 1
    -- marking the last row of the key -- the row the publish step loads.
    -- Reads step 40, the phone branch only.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S5_VERSIONS AS
    SELECT v.*,
           xph.PKEY_SRC_OBJECT IS NULL                                                      AS uq_tgt
      FROM (SELECT d.*,
                   /* TIMELINE */ COUNT(*) OVER (PARTITION BY d.pkey_src_object)                    AS version_seq,
                   ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                      ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC, d.usg_tp DESC,
                                               d.phn_tp DESC, d.phn_num DESC, d.pref_lvl DESC)      AS rn
              FROM (SELECT DISTINCT p.period_start_date, p.pkey_src_object, p.pty_rle_fk, p.usg_tp, p.phn_tp,
                           p.phn_num, p.pref_lvl
                      FROM WRK_TRS_PHN_S4_PHONES p
                     WHERE p.dq_exception_code IS NULL) d) v
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_PHN) xph
             ON xph.PKEY_SRC_OBJECT = v.pkey_src_object AND xph.VERSION_SEQ = v.version_seq;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S5_VERSIONS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PHN_VERSIONS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S5_VERSIONS', 'CREATED',
        'Valid phones only, consolidated and versioned; rn = 1 is the row that loads, uq_tgt is the insert-only guard (BR-06/28). '
        || 'Read by the phone publish branch.',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PHN_VERSIONS', :l_rows) || CHR(10);

    -- ---- Step 60: E-MAILS -- validate (BR-28/29) --------------------------
    -- Purpose: the e-mail branch, independent of the phone branch.
    -- Reads step 10, not step 50.  Rows with a null (trimmed) e-mail
    -- are dropped here; the rest are validated, with the exception
    -- code / description / type resolved and the exception first-row
    -- flag (uq_exc) set exactly as the original final SELECT did for
    -- e-mail-exception rows.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S6_EMAILS AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    emails AS (
        SELECT s.*,
               fn_snow_helper22_common(s.EMAIL)                                AS em
          FROM WRK_TRS_PHN_S1_SRC s
         WHERE TRIM(s.EMAIL) IS NOT NULL
    ),
    emails_checked AS (
        SELECT e.*,
               e.em:email_address::VARCHAR                                     AS std_email,
               xe.EXCEPTION_CODE AS em_exc_code, xe.EXCEPTION_DESC AS em_exc_desc, xe.EXCEPTION_TYPE AS em_exc_type
          FROM emails e
          LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = e.em:exception_code::VARCHAR
    )
    SELECT ec.*,
           -- usg_tp is NULL for every e-mail row, so it does not change the grouping and is omitted here
           ROW_NUMBER() OVER (PARTITION BY TO_VARCHAR(ec.INDV_ID), TO_VARCHAR(ec.CASE_NUM), ec.em_exc_type, ec.em_exc_code
                                  ORDER BY ec.CREATE_DT DESC) = 1                       AS uq_exc
      FROM emails_checked ec;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S6_EMAILS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'EMAILS_CHECKED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S6_EMAILS', 'CREATED',
        'E-mails validated, with exception code / description / type resolved; blank e-mails dropped (BR-28/29). '
        || 'Read by the e-mail-consolidation step and by the e-mail-exception publish branch.',
        NULL, 'Step 60 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 EMAILS_CHECKED', :l_rows) || CHR(10);

    -- ---- Step 70: E-MAIL CONSOLIDATION (BR-06) ---------------------------
    -- Purpose: valid e-mails only, distinct, with a version sequence
    -- equal to the count of distinct versions of the key, and rn = 1
    -- marking the last row of the key -- the row the publish step loads.
    -- Reads step 60, the e-mail branch only.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_PHN_S7_VERSIONS AS
    SELECT v.*,
           xea.PKEY_SRC_OBJECT IS NULL                                                      AS uq_tgt
      FROM (SELECT d.*,
                   /* TIMELINE */ COUNT(*) OVER (PARTITION BY d.pkey_src_object)                    AS version_seq,
                   ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                      ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC,
                                               d.elec_addr DESC)                                    AS rn
              FROM (SELECT DISTINCT e.CREATE_DT AS period_start_date,
                           TO_VARCHAR(e.INDV_ID) || '|Member|001|' || NVL(e.EMAIL, '') AS pkey_src_object,
                           e.PTY_PK || '|Member' AS pty_rle_fk, e.std_email AS elec_addr
                      FROM WRK_TRS_PHN_S6_EMAILS e
                     WHERE e.em_exc_code IS NULL
                       AND e.std_email IS NOT NULL) d) v
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_EADDR) xea
             ON xea.PKEY_SRC_OBJECT = v.pkey_src_object AND xea.VERSION_SEQ = v.version_seq;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_PHN_S7_VERSIONS;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 70,
        'EADDR_VERSIONS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_PHN_S7_VERSIONS', 'CREATED',
        'Valid e-mails only, consolidated and versioned; rn = 1 is the row that loads, uq_tgt is the insert-only guard (BR-06/28). '
        || 'Read by the e-mail publish branch.',
        NULL, 'Step 70 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 70 EADDR_VERSIONS', :l_rows) || CHR(10);

    -- ---- Step 80: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-70 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The four INSERTs below are the four branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the all_kinds CTE to steps 40 / 50 / 60 / 70, and
    -- the original final SELECT's derived columns are computed here
    -- (phone exception splits and attribute, e-mail constants) or
    -- were already computed in the branch work tables (uq_tgt, uq_exc).
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 80a. Valid phones -> C_S_TRS_PTY_RLE_PHN
    INSERT INTO C_S_TRS_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, USG_TP, PHN_TP, PHN_NUM, PREF_LVL, PERIOD_END_DATE, SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, period_start_date, version_seq, NULL, NULL, :l_run_ts, NULL,
           period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, usg_tp, phn_tp, phn_num, pref_lvl,
           NULL, period_start_date
      FROM WRK_TRS_PHN_S5_VERSIONS
     WHERE rn = 1 AND uq_tgt;
    l_rows := l_rows + SQLROWCOUNT;
    -- 80b. Invalid phones -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
            SRC_SYS_ID_2, ATTRIBUTE_NAME)
    SELECT 'TRS', dq_exception_code, dq_exception, :l_run_ts,
           IFF(pref_lvl = 'Primary', phn_num, NULL),
           IFF(usg_tp = 'Work', phn_num, NULL),
           IFF(pref_lvl = 'Secondary', phn_num, NULL),
           :c_mapping, pty_fk, 'Bad Value', usg_tp, period_start_date, phn_num, case_number,
           DECODE(usg_tp, '001', 'Main Phone', '002', 'Work Phone', '003', 'Other Phone')
      FROM WRK_TRS_PHN_S4_PHONES
     WHERE dq_exception_code IS NOT NULL AND uq_exc;
    l_rows := l_rows + SQLROWCOUNT;
    -- 80c. Valid e-mails -> C_S_TRS_PTY_RLE_EADDR
    INSERT INTO C_S_TRS_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, PERIOD_END_DATE,
            SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, period_start_date, version_seq, NULL, NULL, :l_run_ts, NULL,
           period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, elec_addr, NULL, '001',
           'Active', 'Y', NULL, period_start_date
      FROM WRK_TRS_PHN_S7_VERSIONS
     WHERE rn = 1 AND uq_tgt;
    l_rows := l_rows + SQLROWCOUNT;
    -- 80d. Invalid e-mails -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
            PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_2)
    SELECT 'TRS', TO_VARCHAR(INDV_ID), em_exc_code, em_exc_desc, :l_run_ts, EMAIL, :c_mapping, em_exc_type,
           CREATE_DT, EMAIL, 'Email', TO_VARCHAR(CASE_NUM)
      FROM WRK_TRS_PHN_S6_EMAILS
     WHERE em_exc_code IS NOT NULL AND uq_exc;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 80,
        'PUBLISH', 'COMPLETED',
        'C_S_TRS_PTY_RLE_PHN, C_S_TRS_PTY_RLE_EADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: valid phones, valid e-mails and both exception classes. '
        || 'Count shown is the total rows inserted by all four INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 80 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
