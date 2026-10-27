-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Addr_2  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-31  Part 2 of the address load: join TIERS addresses per
--          individual/case to the unique pre-validated addresses from
--          Addr_1, and distribute them to the party-role address
--          staging table.  (Addr_1 validates once; this step distributes.)
--   BR-33  Only fully scored addresses load; low scores are exceptions.
--          Router: Score = '100' -> C_S_TRS_PTY_RLE_ADDR (good path,
--          sorted, version-sequenced); Score = '40' ->
--          EXC_STG_BAD_REC_MEMB.  Records are also written to the
--          DQM_ADDRESS audit table.  Address type is translated through
--          the ADDR_TP crosswalk; an untranslated type scores '40'.
--   BR-20  Dates more than 50 years out are nulled (via
--          mplt_Date_Greater_Than_Fifty_Years -- see Parity notes for
--          the exact Snowflake behaviour, which is preserved, not fixed).
--   BR-07  Timeline discipline: VERSION_SEQ, PERIOD_REFERENCE_TIME,
--          period start/end dates are calculated per role-address key.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (addr_de_dup ->
--   src -> keyed -> scored -> final SELECT), one transaction, one log
--   line at the end.  If it failed, nothing told you which logical
--   stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_ADDR2_S10_DEDUP   latest address per indv / type / case / EDG
--   Step 20  WRK_TRS_ADDR2_S20_SRC      deduped rows joined to validated unique
--                                      addresses + valid members
--   Step 30  WRK_TRS_ADDR2_S30_KEYED    address-type translation, result postcode,
--                                      role-address key, 50-year end-date rule
--   Step 40  WRK_TRS_ADDR2_S40_SCORED   score + issue description + VERSION_SEQ
--   Step 50  WRK_TRS_ADDR2_S50_READY    publish-ready rows: audit keys, hold lines,
--                                      exception attributes/codes, uniqueness guards
--   Step 60  PUBLISH                    DQM_ADDRESS + C_S_TRS_PTY_RLE_ADDR +
--                                      EXC_STG_BAD_REC_MEMB, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_ADDR2_S10_DEDUP, WRK_TRS_ADDR2_S20_SRC, WRK_TRS_ADDR2_S30_KEYED,
--   WRK_TRS_ADDR2_S40_SCORED, WRK_TRS_ADDR2_S50_READY.  They live in the
--   same schema as the targets (unqualified names, as in the original
--   code), are prefixed WRK_TRS_, and are registered in
--   JOB_CONTROL_ETL at creation.  They survive a session
--   crash (TRANSIENT, not TEMP), which is what makes inspection after a run possible; a
--   pure session TEMP table would vanish with the session and could
--   never be available after a crash.  A Snowflake CURSOR was NOT used: cursors
--   process row by row, and every step here is set-based by design --
--   the work table IS the result set, held as a table instead of in
--   memory, so it can be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_ADDR first; the
--     Snowflake version instead skips keys already present (the uq_addr
--     guard in step 50, on PKEY_SRC_OBJECT + VERSION_SEQ, and the
--     uq_addr_exc guard for exceptions).  A re-run therefore inserts
--     nothing twice, but it also does not remove rows that IDQ would
--     have truncated away -- see the User Guide, "Parity gaps".
--   * Score rules, exactly as in the original: only '100' loads and only
--     '40' is exceptioned.  The IDQ Default router branch is not linked
--     ("the score is always '40' or '100"), so a row with any other
--     score is written to DQM_ADDRESS (the WHEN TRUE audit branch) and
--     to neither staging nor exceptions.  That behaviour is preserved
--     here; if a new score ever appears, it will be visible in
--     DQM_ADDRESS and nowhere else, which is the signal to revisit it.
--   * 50-year rule quirk, preserved: fn_snow_helper21_common reproduces
--     the IDQ comparison of the year difference as TEXT with '50', so
--     end dates more than 50 years away AND end dates 6 to 10 years away
--     become NULL (open).  Do not "correct" this helper without also
--     changing the business rule, because PERIOD_END_DATE and EFF_END_DT
--     both carry its result.
--   * The source's "select distinct" flag is ignored by IDQ when custom
--     SQL is used, so it is not applied here either, as in the original.
--   * Unfed ports written as NULL, as in the original: ROWID_OBJECT,
--     DELETED_*, UPDATED_BY, HUB_STATE_IND, USG_TP, CRDNT_SYS, PSTL_BRCD,
--     RGN_CD, CREATOR, CREATE_DATE, LCTN_CRDNT_DESC (sorter port without
--     input -- note step 50 does populate LOC_IDN from CASE_NUM/EDG_NUM).
--   * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set, else NULL.
--   * VERSION_SEQ is a running number per role-address key in (key,
--     SRC_LAST_UPDATE_DATE desc, EFF_END_DT desc, EFF_BEGIN_DT desc;
--     NULL high) order -- every row is written, numbered 1, 2, 3, ...
--     within the key.  SRC_ROWID = key || '|' || VERSION_SEQ.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Addr_2 (
    P_MEMBER_ROLE_TYPE      VARCHAR DEFAULT 'Member',
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr',
    P_JOB_RUN_ID            VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_workflow   VARCHAR DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_source     VARCHAR DEFAULT 'TRS';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Addr_2';
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
    DROP TABLE IF EXISTS WRK_TRS_ADDR2_S10_DEDUP;
    DROP TABLE IF EXISTS WRK_TRS_ADDR2_S20_SRC;
    DROP TABLE IF EXISTS WRK_TRS_ADDR2_S30_KEYED;
    DROP TABLE IF EXISTS WRK_TRS_ADDR2_S40_SCORED;
    DROP TABLE IF EXISTS WRK_TRS_ADDR2_S50_READY;


    -- ---- Step 10: DE-DUPLICATE ADDRESSES (BR-31) ------------------------
    -- Purpose: the latest address per individual / address type / case /
    -- EDG.  The address identity is the concatenated address parts
    -- (addr_id).  The ordering uses greatest(create_dt, nvl(update_dt,
    -- create_dt)) -- the original comment notes there is junk data where
    -- create is after update -- then eff_begin_dt desc.  Only key_rn = 1
    -- survives, in step 20.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR2_S10_DEDUP AS
    SELECT a.indv_id, a.case_num, a.edg_num, a.addr_type_cd,
           NVL(TO_VARCHAR(a.addr_st_num), '') || '|' || NVL(a.addr_st_num_frac, '') || '|'
           || NVL(a.addr_st_nm, '') || '|' || NVL(a.addr_st_dir_cd, '') || '|' || NVL(a.addr_st_type_cd, '')
           || '|' || NVL(a.addr_dwelling_type_cd, '') || '|' || NVL(a.addr_apt_num, '') || '|'
           || NVL(a.addr_line, '') || '|' || NVL(a.addr_city, '') || '|' || NVL(a.addr_state_cd, '') || '|'
           || NVL(TO_VARCHAR(a.addr_zip5), '') || '|' || NVL(TO_VARCHAR(a.addr_zip4), '') AS addr_id,
           GREATEST(a.create_dt, NVL(a.update_dt, a.create_dt)) AS create_dt, a.eff_begin_dt, a.eff_end_dt,
           ROW_NUMBER() OVER (PARTITION BY a.indv_id, a.addr_type_cd, a.case_num, a.edg_num
                              ORDER BY GREATEST(a.create_dt, NVL(a.update_dt, a.create_dt)) DESC,
                                       a.eff_begin_dt DESC) AS key_rn
      FROM STG_TRS_D_INDV_ADDR a;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR2_S10_DEDUP;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ADDR_DEDUP', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR2_S10_DEDUP', 'CREATED',
        'Latest address per individual / address type / case / EDG, keyed by address parts (BR-31). '
        || 'Only key_rn = 1 is used, in step 20.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ADDR_DEDUP', :l_rows) || CHR(10);

    -- ---- Step 20: JOIN TO VALIDATED ADDRESSES + VALID MEMBERS -----------
    -- Purpose: the deduped rows (key_rn = 1 only) joined to the
    -- pre-validated unique addresses from Addr_1 (STG_TRS_D_UNQ_ADDR, on
    -- addr_id) and to the valid-member spine (STG_TRS_VALID_MEMBERS, on
    -- indv_id).  The join to valid members is what keeps addresses for
    -- non-valid members out of the load.  Reads ONLY step 10.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR2_S20_SRC AS
    SELECT a.indv_id AS INDV_ID, a.case_num AS CASE_NUM, a.edg_num AS EDG_NUM, vm.pty_pk AS PTY_PK,
           a.addr_type_cd AS ADDR_TYPE_CD, a.create_dt AS CREATE_DT, a.eff_begin_dt AS EFF_BEGIN_DT,
           a.eff_end_dt AS EFF_END_DT, u.addr_id AS ADDR_ID, u.addr_ln_1 AS ADDR_LN_1, u.addr_ln_2 AS ADDR_LN_2,
           u.bldng_nm AS BLDNG_NM, u.flr_num AS FLR_NUM, u.city AS CITY, u.county AS COUNTY, u.state AS STATE,
           u.cntry_cd AS CNTRY_CD, u.pstl_cd AS PSTL_CD, u.pstl_cd_ext AS PSTL_CD_EXT, u.lattd AS LATTD,
           u.lngtd AS LNGTD, u.vldtn_msg AS VLDTN_MSG, u.vldtn_desc AS VLDTN_DESC, u.mlblty_scr AS MLBLTY_SCR,
           u.addr_tp_cd AS ADDR_TP_CD, u.org_desc AS ORG_DESC, u.org_dept AS ORG_DEPT, u.org_nm AS ORG_NM,
           u.bldg_nmbr AS BLDG_NMBR, u.sub_bldg_nm AS SUB_BLDG_NM, u.sub_bldg_desc AS SUB_BLDG_DESC,
           u.geocd_sts_cd AS GEOCD_STS_CD, u.rsdntl_dlvry_ind AS RSDNTL_DLVRY_IND,
           u.addrdr_rslt_pct AS ADDRDR_RSLT_PCT, u.erly_wrng_cd AS ERLY_WRNG_CD, u.cass_err_cd AS CASS_ERR_CD,
           u.dlvry_pnt_vldn AS DLVRY_PNT_VLDN, u.src_addr_ln_1 AS SRC_ADDR_LN_1,
           u.src_addr_ln_2 AS SRC_ADDR_LN_2, u.src_city AS SRC_CITY, u.src_county AS SRC_COUNTY,
           u.src_state AS SRC_STATE, u.src_cntry AS SRC_CNTRY, u.src_pstl_cd AS SRC_PSTL_CD,
           u.src_pstl_cd_ext AS SRC_PSTL_CD_EXT
      FROM WRK_TRS_ADDR2_S10_DEDUP a
      JOIN STG_TRS_D_UNQ_ADDR u ON a.addr_id = u.addr_id
      JOIN STG_TRS_VALID_MEMBERS vm ON a.indv_id = vm.indv_id
     WHERE a.key_rn = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR2_S20_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'SRC_VALIDATED_JOIN', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR2_S20_SRC', 'CREATED',
        'Deduped addresses joined to validated unique addresses (Addr_1) and valid members (BR-31). '
        || 'Read by the keying step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 SRC_VALIDATED_JOIN', :l_rows) || CHR(10);

    -- ---- Step 30: ADDRESS-TYPE TRANSLATION + ROLE-ADDRESS KEY -----------
    -- Purpose: lkp_Address_Type (V_LOOKUP_CODE_VALUE, ADDR_TP, 'TRS') +
    -- Exp_src_defaults + the role-address key + the 50-year end-date
    -- rule.  The key is PTY_PK | role type | master address type |
    -- case | EDG | EFF_BEGIN_DT (YYYYMMDD).  Reads ONLY step 20.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR2_S30_KEYED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT s.*,
           at.MSTR_CODE_VALUE                                                                    AS mstr_addr_tp,
           NVL(s.PSTL_CD, '') || IFF(s.PSTL_CD_EXT IS NOT NULL, '-' || s.PSTL_CD_EXT, '')         AS rslt_pstl_cd,
           NVL(s.PTY_PK, '') || '|' || :P_MEMBER_ROLE_TYPE || '|' || NVL(at.MSTR_CODE_VALUE, '') || '|'
           || NVL(TO_VARCHAR(s.CASE_NUM), '') || '|' || NVL(TO_VARCHAR(s.EDG_NUM), '') || '|'
           || NVL(TO_VARCHAR(s.EFF_BEGIN_DT, 'YYYYMMDD'), '')                                    AS pkey_pty_rle_addr,
           fn_snow_helper21_common(s.EFF_END_DT, :l_run_ts)                                       AS end_date_50y
      FROM WRK_TRS_ADDR2_S20_SRC s
      LEFT JOIN lkp_cv at ON at.CODE_TYPE = 'ADDR_TP' AND at.SRC_SYS = 'TRS' AND at.SRC_CODE_VALUE = s.ADDR_TYPE_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR2_S30_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'KEYED_ADDR', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR2_S30_KEYED', 'CREATED',
        'Address-type translation, result postcode, role-address key and 50-year end-date rule (BR-07, BR-20). '
        || 'Read by the scoring step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 KEYED_ADDR', :l_rows) || CHR(10);

    -- ---- Step 40: SCORE + VERSION SEQUENCE (BR-33, BR-07) ---------------
    -- Purpose: exp_Score_and_Exception_details + the sorter / attribute
    -- hold that assigns VERSION_SEQ.  The score comes from the master
    -- address type, the mailability score and the AddressDoctor match
    -- code of Addr_1 (VLDTN_MSG); an address type that does not translate
    -- scores '40'.  VERSION_SEQ runs 1, 2, 3, ... within each
    -- role-address key.  Reads ONLY step 30.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR2_S40_SCORED AS
    SELECT k.*,
           fn_snow_helper05_common(k.mstr_addr_tp, k.MLBLTY_SCR, k.VLDTN_MSG)     AS score,
           fn_snow_helper06_common(k.mstr_addr_tp, k.MLBLTY_SCR, k.VLDTN_MSG)     AS addr_issue_desc,
           ROW_NUMBER() OVER (PARTITION BY k.pkey_pty_rle_addr
                              ORDER BY k.CREATE_DT DESC NULLS FIRST, k.EFF_END_DT DESC NULLS FIRST,
                                       k.EFF_BEGIN_DT DESC NULLS FIRST)          AS version_seq
      FROM WRK_TRS_ADDR2_S30_KEYED k;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR2_S40_SCORED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'SCORED_VERSIONED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR2_S40_SCORED', 'CREATED',
        'Scored addresses with VERSION_SEQ per role-address key (BR-33, BR-07). '
        || 'Read by the ready step, which applies the 100 / 40 router.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 SCORED_VERSIONED', :l_rows) || CHR(10);

    -- ---- Step 50: READY -- audit keys, hold lines, exception data -------
    -- Purpose: the original final SELECT, as a table.  It adds the audit
    -- keys (DQM_ADDRESS), the hold lines, the exception attribute/value
    -- and the looked-up 'Invalid_Address' code, and the two uniqueness
    -- guards: uq_addr (key + VERSION_SEQ not already in
    -- C_S_TRS_PTY_RLE_ADDR -- the insert-only guard) and uq_addr_exc
    -- (first row per score / individual / case / EDG for exceptions).
    -- Reads ONLY step 40 (plus the exception lookup and the target guard).
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR2_S50_READY AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT c.*,
           'TRS'                                                                AS src_sys,
           :l_run_ts                                                            AS run_ts,
           :c_mapping                                                           AS mapping_name,
           :P_MEMBER_HIERARCHY_CODE                                             AS hierarchy_code,
           :P_MEMBER_HM_REL_TP_CD                                               AS hm_rel_tp_cd,
           'Primary'                                                            AS pref_lvl,
           IFF(c.EFF_END_DT IS NOT NULL, :l_run_ts, NULL)                        AS period_reference_time,
           c.pkey_pty_rle_addr || '|' || TO_VARCHAR(c.version_seq)               AS src_rowid,
           NVL(TO_VARCHAR(TRUNC(c.CASE_NUM)), '') || '|' || NVL(TO_VARCHAR(TRUNC(c.EDG_NUM)), '') AS loc_idn,
           NVL(c.PTY_PK, '') || '|' || :P_MEMBER_ROLE_TYPE                      AS pty_rle_fk,
           fn_snow_helper07_common(c.ADDR_LN_1, c.ADDR_LN_2)                    AS hold_line1,
           fn_snow_helper08_common(c.ADDR_LN_1, c.ADDR_LN_2)                    AS hold_line2,
           NVL(c.ADDR_LN_1, '') || '|' || NVL(c.ADDR_LN_2, '') || '|' || NVL(c.CITY, '') || '|' || c.rslt_pstl_cd
           || '|' || NVL(c.STATE, '') || '|' || NVL(c.CNTRY_CD, '')             AS dqm_addr_src_key,
           NVL(c.SRC_PSTL_CD, '') || IFF(c.SRC_PSTL_CD_EXT IS NOT NULL, '-' || c.SRC_PSTL_CD_EXT, '') AS dqm_src_pstl_cd,
           IFF(c.addr_issue_desc IS NOT NULL, 'Address', NULL)                  AS exc_attribute_name,
           IFF(c.addr_issue_desc IS NOT NULL,
               NVL(c.SRC_ADDR_LN_1, '') || ' ' || NVL(c.SRC_ADDR_LN_2, '') || ' ' || NVL(c.SRC_CITY, '') || ' '
               || NVL(c.SRC_STATE, '') || ' ' || NVL(TO_VARCHAR(c.SRC_PSTL_CD), '') || ' '
               || NVL(TO_VARCHAR(c.SRC_PSTL_CD_EXT), '') || ' ' || NVL(c.SRC_CNTRY, ''), NULL) AS exc_attribute_value,
           ex.EXCEPTION_CODE                                                    AS exc_code,
           ex.EXCEPTION_DESC                                                    AS exc_desc,
           ex.EXCEPTION_TYPE                                                    AS exc_type,
           xa.PKEY_SRC_OBJECT IS NULL                                           AS uq_addr,
           ROW_NUMBER() OVER (PARTITION BY c.score, c.INDV_ID, c.CASE_NUM, c.EDG_NUM
                                  ORDER BY c.CREATE_DT DESC, c.ADDR_TYPE_CD) = 1 AS uq_addr_exc
      FROM WRK_TRS_ADDR2_S40_SCORED c
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Address'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_ADDR) xa
             ON xa.PKEY_SRC_OBJECT = c.pkey_pty_rle_addr AND xa.VERSION_SEQ = c.version_seq;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR2_S50_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'READY_TO_PUBLISH', 'COMPLETED',
        'DQM_ADDRESS, C_S_TRS_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_TRS_ADDR2_S50_READY', 'CREATED',
        'Publish-ready addresses: audit keys, hold lines, exception data and uniqueness guards '
        || '(uq_addr, uq_addr_exc). Published in step 60; only score 100 loads, only score 40 is exceptioned (BR-33).',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 60: PUBLISH -- one transaction, three targets -------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-50 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The three INSERTs below are the three branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final SELECT to step 50.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 60a. Write_DQM_ADDRESS (every row)
    INSERT INTO DQM_ADDRESS
           (ADDR_SRC_KEY, SRC_SYSTEM, PTY_SRC_KEY, LOAD_DT, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_CNTRY,
            RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_STATE, RSLT_CNTRY, COUNTY_FIPS, STATE_FIPS, LATTD, LNGTD,
            RSLT_PSTL_CD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG, SUB_BLDG, MLBLTY_SCR, ADDRDR_MTCH_CD,
            ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, RSLT_COUNTY, ORG_DEPT,
            ORG_NM, SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, MDM_ADDR_TP)
    SELECT dqm_addr_src_key, src_sys, PTY_PK, run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_CNTRY,
           ADDR_LN_1, ADDR_LN_2, CITY, STATE, CNTRY_CD, COUNTY, STATE, LATTD, LNGTD, rslt_pstl_cd,
           GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG_NMBR, SUB_BLDG_NM, MLBLTY_SCR, VLDTN_MSG,
           ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDR_TP_CD, COUNTY, ORG_DEPT, ORG_NM,
           SRC_COUNTY, SRC_STATE, dqm_src_pstl_cd, ADDR_TYPE_CD
      FROM WRK_TRS_ADDR2_S50_READY;
    l_rows := l_rows + SQLROWCOUNT;
    -- 60b. Good -> Write_C_S_TRS_PTY_RLE_ADDR (score 100, not already loaded)
    INSERT INTO C_S_TRS_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, HIERARCHY_CODE, HM_REL_TP_CD,
            LAST_UPDATE_DATE, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, UPDATED_BY, SRC_ROWID,
            HUB_STATE_IND, PREF_LVL, LOC_IDN, ADDR_TP, PTY_RLE_FK, USG_TP, ADDR_LN_1, ADDR_LN_2, CITY, PSTL_CD,
            PSTL_CD_EXT, CNTRY_CD, CRDNT_SYS, LATTD, LNGTD, PSTL_BRCD, FLR_NUM, BLDNG_NM, COUNTY, STATE,
            LCTN_CRDNT_DESC, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, GEOCD_STS_CD,
            SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
            SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, CREATOR, CREATE_DATE,
            EFF_STRT_DT, PERIOD_END_DATE, EFF_END_DT)
    SELECT pkey_pty_rle_addr, EFF_BEGIN_DT, version_seq, period_reference_time, hierarchy_code, hm_rel_tp_cd,
           run_ts, NULL, NULL, NULL, NULL, NULL, src_rowid, NULL, pref_lvl, loc_idn, mstr_addr_tp, pty_rle_fk,
           NULL, hold_line1, hold_line2, CITY, PSTL_CD, PSTL_CD_EXT, CNTRY_CD, NULL, LATTD, LNGTD, NULL,
           FLR_NUM, BLDNG_NM, COUNTY, STATE, NULL, VLDTN_MSG, NULL, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM,
           GEOCD_STS_CD, SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
           SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, CREATE_DT,
           NULL, NULL, EFF_BEGIN_DT, end_date_50y, end_date_50y
      FROM WRK_TRS_ADDR2_S50_READY
     WHERE score = '100' AND uq_addr;
    l_rows := l_rows + SQLROWCOUNT;
    -- 60c. Exception -> EXC_STG_BAD_REC_MEMB (score 40, first per score/case)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE, RUN_DATE,
            ADDRESS_LINE_1, ADDRESS_LINE_2, ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP,
            ADDRESS_ZIP_EXT, ADDRESS_COUNTRY, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT src_sys, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, exc_attribute_name, exc_attribute_value, mapping_name,
           ADDR_TYPE_CD, EFF_BEGIN_DT, EFF_END_DT, run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
           SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_CNTRY, INDV_ID, CASE_NUM, EDG_NUM,
           exc_code, exc_desc, exc_type
      FROM WRK_TRS_ADDR2_S50_READY
     WHERE score = '40' AND uq_addr_exc;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'PUBLISH', 'COMPLETED',
        'DQM_ADDRESS, C_S_TRS_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: DQM_ADDRESS audit for every row, good addresses (score 100) to '
        || 'C_S_TRS_PTY_RLE_ADDR, exception addresses (score 40) to EXC_STG_BAD_REC_MEMB (BR-33). '
        || 'Count shown is rows inserted across all three targets.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 PUBLISH (all targets)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Addr_2 completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Addr_2 failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
