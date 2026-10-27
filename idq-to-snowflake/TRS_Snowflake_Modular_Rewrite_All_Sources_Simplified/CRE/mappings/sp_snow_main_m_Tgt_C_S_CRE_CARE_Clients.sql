-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients  --  MODULAR REWRITE (simplified v2)
--
-- IDQ mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing
-- (its only mapping).
--
-- Loads the CARE clients into CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE,
-- C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN and C_S_CRE_PTY_RLE_ALT_ID
-- (insert only, never truncated) and logs exceptions:
--   -> new and changed clients ('I'), deleted ('D') and moved ('B') cases
--      from the snapshot STG_CRE_SN_CARE_CLIENTS through
--      STG_CRE_D_CARE_CASE_MAINT, and the targets of the moves ('A')
--   -> merge routing: rows that are not regular or deleted (the DELETES
--      group) look the source and target CARE ids up in C_B_PTY_XREF and
--      their original records in C_B_PTY_HMRG; no merge history at all
--      goes to CRE_SRC_MRG
--   -> name standardisation; a member needs a standardised first AND last
--      name, otherwise the missing name is logged
--   -> one row per CARE id (record type descending: I, D, B, A) -> party,
--      role, address (US: address validation; abroad: state 99, country
--      ZZ), phone, and the three alternate ids (CARE ID, Medicaid ID, SSN)
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> xref /
--   hmrg -> routed -> named -> members -> ranked -> dq -> dq2 -> alt_tp
--   -> flat -> keyed -> final select), one transaction, one summary line
--   at the end.  If it failed, nothing told you which logical stage had
--   finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTEs, with their FROM
--   clauses pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target / exception class)
--   inside ONE transaction, so a publish either lands completely or not
--   at all.  A single source row can still land in several targets, as
--   in INSERT ALL: the separate INSERTs each read the same work table
--   with their own original WHEN condition.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_CRE_CARE_S1_SRC_MRG   CARE snapshot + merge routing
--          (src + xref + hmrg + routed)
--   Step 20  WRK_CRE_CARE_S2_NAMED     name standardisation + member
--          validity (named + members)
--   Step 30  WRK_CRE_CARE_S3_RANKED    rank per CARE id + validation
--          enrichment: gender, ethnicity, race, phone, CARE / Medicaid /
--          SSN checks, US address validation (ranked + dq + dq2)
--   Step 40  WRK_CRE_CARE_S4_FLAT      flattened load-ready rows: US vs
--          abroad address split, phone key, alternate-id keys/values,
--          exception codes, timeline dates (alt_tp + flat)
--   Step 50  WRK_CRE_CARE_S5_KEYED     route flags + insert-only
--          unique-key guards (keyed + final select)
--   Step 60  PUBLISH                   targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN       drop any work tables left by the
--                                     previous run (step 5, drops only,
--                                     no checkpoint), then rebuild
--                                     from step 10
--   End    TERMINATING                work tables are NOT dropped: they
--                                     stay in the database until the next
--                                     run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_CRE_CARE_S1_SRC_MRG, WRK_CRE_CARE_S2_NAMED,
--   WRK_CRE_CARE_S3_RANKED, WRK_CRE_CARE_S4_FLAT,
--   WRK_CRE_CARE_S5_KEYED.  They live in the same schema as the targets
--   (unqualified names, as in the original code), are prefixed WRK_CRE_,
--   and are registered in the shared job-control table at creation.
--   They survive a session crash (TRANSIENT, not TEMP), which is what
--   makes inspection after a run possible.  A Snowflake CURSOR was NOT
--   used: every step here is set-based by design -- the work table IS
--   the result set, held as a table instead of in memory, so it can be
--   counted and inspected after the run.
--
-- INSTALL
--   All table names are unqualified, as in the original code.  Install
--   this procedure in schema CRE_ETL_WRK in database MDM_ETL_CRE, so
--   unqualified names resolve to that schema's tables.  The control
--   procedures (sp_etl_job_begin / sp_etl_checkpoint / sp_etl_job_finish
--   / sp_etl_job_fail) are the shared multi-source framework's, called
--   with SOURCE first (:c_source = 'CRE').
--
-- VALIDATION (helpers, all from the shared common files -- none invented)
--   fn_snow_helper15_common (name, with the SUFFIX and junk-name
--   lookups), fn_snow_helper17_common (gender), fn_snow_helper18_common
--   with V_LOOKUP_CODE_VALUE ETHNICITY / RACE, fn_snow_helper23_common
--   and fn_snow_helper24_common (phone, only the number linked: no
--   toll-free check for CRE), fn_snow_helper27_common (Medicaid id),
--   fn_snow_helper26_common (SSN), fn_snow_helper37_common (CARE id),
--   fn_snow_helper34_common (address) and the valid-address rule:
--   (TO_INTEGER(mailability score) >= 3 OR match code not starting I / N)
--   AND a state FIPS; abroad the city and street must be present.  No
--   birth-date rule.  The name, phone and SSN routes and the address,
--   gender, ethnicity and race exception rows use the code AS LOOKED UP
--   in EXC_LOOKUP_CODE_VALUE (fn_snow_helper40_common): unconfigured
--   means no name row, a loaded phone or SSN, an address row with a NULL
--   code, no gender / ethnicity / race row.  The suffix and Medicaid
--   rows write the computed code.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  IDQ truncates the targets; the Snowflake
--     version instead skips keys already present (uq_pty / uq_rle /
--     uq_addr / uq_phone / uq_care_alt / uq_medicaid_alt / uq_ssn_alt
--     guards, VERSION_SEQ = 1 in the targets).  A re-run therefore
--     inserts nothing twice, but it also does not remove rows that IDQ
--     would have truncated away.
--   * Invalid members are logged and dropped; a bad address, phone or
--     alternate id is logged instead of loaded (the member itself is
--     still loaded).  SSN 'U' / 'N' is blanked and dropped; CARE and
--     Medicaid ids of 'U' / 'N' are blanked for the loaded value (the
--     key still uses the raw id).  Ids lose special characters (inside
--     the helpers) and are cut to 10 characters; phones are cut to 10
--     digits; SRC_ROWID is cut to 30 characters (IDQ truncates to the
--     target precision).
--   * With the pass-through address validator (no score, no match code)
--     the valid-US-address condition is NULL, so every US address is an
--     exception (the NVL(..., FALSE) in the flat step).
--   * TIMELINE: VERSION_SEQ = VERSION_SEQ_NUM (the rank per CARE id; 1
--     for every written row).  'B' and 'D' rows are end-dated:
--     PERIOD_START_DATE = CARE_LASTUP_DT - 1 day, PERIOD_END_DATE =
--     CARE_LASTUP_DT, TIMELINE_ACTION = 2, PERIOD_REFERENCE_TIME =
--     PERIOD_START_DATE, LAST_UPDATE_DATE = run start - 1 hour (the role
--     keeps the run start).  The role and the alternate ids do not link
--     TIMELINE_ACTION / PERIOD_REFERENCE_TIME (written NULL).
--   * IDQ quirks kept: CRE_SRC_MRG also gets moves whose CARE ids have
--     no cross-reference (NULL records), and the move target row again
--     when it carries a MAINT_FLAG; the CARE ID alternate id of an
--     unmerged move is the target id (mrg_care_id); the state and
--     alternate-id type lookups have no code-type filter
--     (fn_snow_helper42_common / LOOKUP_CODE_VALUE by source value), so
--     an untranslated type leaves ALT_ID_TP and the exception's SRC_SYS
--     NULL; the alternate-id type pick is the first row ordered by
--     CODE_TYPE.  The phone exception and the address exception rows
--     have no unique-key guard in the original, and none was added.
--     member_rle_fk hard-codes 'Member' while rle_key uses the
--     P_RLE_BO_CLASS_CD_MEMBER parameter (both are 'Member' at the
--     defaults, so they agree unless the parameter is overridden).
--   * The exception rows for a CARE id read twice (name rows) and the
--     Medicaid / SSN rows that the source and the target of an unmerged
--     move both log under the target id are de-duplicated by the
--     uq_first_name / uq_last_name / uq_medicaid_exc / uq_ssn_exc
--     guards, exactly as in the original.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients (
    P_PHYSICAL_ADDR_TYPE_CD  VARCHAR DEFAULT '002',
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',
    P_DEFAULT_TX_STATE_CD    VARCHAR DEFAULT '48',
    P_COUNTY_CD_NONTX        VARCHAR DEFAULT '996',
    P_COUNTYCD_DEFAULTALL    VARCHAR DEFAULT '998',
    P_DEFAULT_NONUS_STATE_CD VARCHAR DEFAULT '99',
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'CRE';
    c_workflow   VARCHAR DEFAULT 'wf_CRE_Stage_Load_Ongoing';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_CRE_CARE_Clients';
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
            'CRE_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    -- No checkpoint is written for these drops.
    DROP TABLE IF EXISTS WRK_CRE_CARE_S1_SRC_MRG;
    DROP TABLE IF EXISTS WRK_CRE_CARE_S2_NAMED;
    DROP TABLE IF EXISTS WRK_CRE_CARE_S3_RANKED;
    DROP TABLE IF EXISTS WRK_CRE_CARE_S4_FLAT;
    DROP TABLE IF EXISTS WRK_CRE_CARE_S5_KEYED;

    -- ---- Step 10: SOURCE SNAPSHOT + MERGE ROUTING ------------------------
    -- Purpose: the CARE client snapshot -- new and changed clients ('I'
    -- rows, MAINT_FLAG IS NULL), deleted and moved cases ('D' / 'B' rows
    -- from the snapshot through the case-maintenance table), and the
    -- targets of the moves ('A' rows) -- with the merge routing: the
    -- source and target CARE ids looked up in the party cross-reference
    -- (first cross-reference row per source key) and their original
    -- records checked against the merge history.  Rows that are not
    -- regular or deleted, with no merge history at all, are the ones
    -- the publish step writes to CRE_SRC_MRG.  Every later step reads
    -- this table, never the raw sources again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_CRE_CARE_S1_SRC_MRG AS
    WITH
    -- Read_Stg_CRE_D_CARE_Clients (custom SQL; the parallel hint and commented test filters left out)
    src AS (
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
               CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN,
               CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, CAST(NULL AS VARCHAR) AS SOURCE_ID,
               CAST(NULL AS VARCHAR) AS TARGET_ID, CAST(NULL AS VARCHAR) AS REC, 'I' AS REC_TYPE
          FROM STG_CRE_D_CARE_CLIENTS CLIENTS
         WHERE CLIENTS.MAINT_FLAG IS NULL
        UNION ALL
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
               CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, DELTAS.MAINT_FLAG, CLIENTS.SSN,
               CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
               DECODE(MAINT.REC, 'CASEMOV', 'B', 'D')
          FROM STG_CRE_D_CARE_CLIENTS DELTAS
          LEFT JOIN STG_CRE_SN_CARE_CLIENTS CLIENTS
            ON DELTAS.CARE_ID = CLIENTS.CARE_ID
          JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
            ON CLIENTS.CARE_ID = MAINT.SOURCE_ID
           AND DELTAS.MAINT_FLAG = 'D'
           AND MAINT.REC IN ('CASEMOV', 'CASEDEL')
        UNION ALL
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
               CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN,
               CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
               'A' AS REC_TYPE
          FROM STG_CRE_SN_CARE_CLIENTS CLIENTS
          JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
            ON CLIENTS.CARE_ID = MAINT.TARGET_ID
           AND MAINT.REC = 'CASEMOV'
    ),
    -- LKP_XREF_SRC / LKP_XREF_TGT: CHAR columns are not compared blank-padded in Snowflake, hence the trims
    xref AS (
        SELECT x.PKEY_SRC_OBJECT, RTRIM(x.ROWID_OBJECT) AS ROWID_OBJECT,
               RTRIM(x.ORIG_ROWID_OBJECT) AS ORIG_ROWID_OBJECT
          FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'CRE'
       QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.ROWID_XREF) = 1
    ),
    -- LKP_HMRG_SRC1 / LKP_HMRG_TGT1 (by SRC_ROWID_OBJECT) and LKP_HMRG_SRC2 / LKP_HMRG_TGT2 (by TGT_ROWID_OBJECT)
    hmrg_src AS (SELECT DISTINCT RTRIM(SRC_ROWID_OBJECT) AS ROWID_OBJECT FROM C_B_PTY_HMRG
                  WHERE SRC_ROWID_OBJECT IS NOT NULL),
    hmrg_tgt AS (SELECT DISTINCT RTRIM(TGT_ROWID_OBJECT) AS ROWID_OBJECT FROM C_B_PTY_HMRG
                  WHERE TGT_ROWID_OBJECT IS NOT NULL)
    -- RTR_MERGES (VALIDATION: NULL conditions route to the default group) + EXP_SRC_TGT_MRG_RSLT
    SELECT s.*,
           NVL(s.MAINT_FLAG IS NULL OR (s.MAINT_FLAG = 'D' AND s.REC = 'CASEDEL'), FALSE) AS grp_deletes,
           xs.ROWID_OBJECT AS src_rowid_object,
           xt.ROWID_OBJECT AS tgt_rowid_object,
           (h1.ROWID_OBJECT IS NULL AND h2.ROWID_OBJECT IS NULL AND h3.ROWID_OBJECT IS NULL
            AND h4.ROWID_OBJECT IS NULL) AS no_merge_history
      FROM src s
      LEFT JOIN xref xs ON xs.PKEY_SRC_OBJECT = s.SOURCE_ID
      LEFT JOIN xref xt ON xt.PKEY_SRC_OBJECT = s.TARGET_ID
      LEFT JOIN hmrg_src h1 ON h1.ROWID_OBJECT = xs.ORIG_ROWID_OBJECT
      LEFT JOIN hmrg_tgt h2 ON h2.ROWID_OBJECT = xs.ORIG_ROWID_OBJECT
      LEFT JOIN hmrg_src h3 ON h3.ROWID_OBJECT = xt.ORIG_ROWID_OBJECT
      LEFT JOIN hmrg_tgt h4 ON h4.ROWID_OBJECT = xt.ORIG_ROWID_OBJECT;
    SELECT COUNT(*) INTO :l_rows FROM WRK_CRE_CARE_S1_SRC_MRG;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_MERGE_ROUTING', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_CRE_CARE_S1_SRC_MRG', 'CREATED',
        'CARE client snapshot (new/changed, deleted, moved, move targets) with merge routing from the '
        || 'party cross-reference and merge history. Read by the name step; never re-read the raw sources after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_MERGE_ROUTING', :l_rows) || CHR(10);

    -- ---- Step 20: NAME STANDARDISATION + MEMBER VALIDITY -----------------
    -- Purpose: one standardised row per source record, and the
    -- valid-member flag: a member needs a standardised first AND last
    -- name, otherwise the missing name is recorded for the exception
    -- step and the row is dropped from the load.  'B' / 'D' rows are
    -- flagged end_dated here (their timeline dates are built in step
    -- 40).  Reads ONLY WRK_CRE_CARE_S1_SRC_MRG (plus the reference
    -- lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_CRE_CARE_S2_NAMED AS
    WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    -- Union + mplt_Name_Standardization_Indv_Member (first, last, suffix and source system linked)
    named AS (
        SELECT r.*,
               IFF(r.grp_deletes, NULL, IFF(r.no_merge_history, 'N', 'Y'))            AS orig_rowid_object_desc,
               fn_snow_helper15_common(r.FIRSTNM, NULL, r.LASTNM, NULL, NULL, r.LAST_SUF, NULL,
                                       sf.MSTR_CODE_VALUE, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
          FROM WRK_CRE_CARE_S1_SRC_MRG r
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(r.FIRSTNM)) AND jf.IS_FIRST_JUNK
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(r.LASTNM)) AND jl.IS_LAST_JUNK
          LEFT JOIN lkp_cv sf ON sf.CODE_TYPE = 'SUFFIX' AND sf.SRC_SYS = 'CRE' AND sf.SRC_CODE_VALUE = r.LAST_SUF
    )
    -- rtr_Valid_Members, EXP_INVALID_MEMBERS, EXP_VALID_MEMBERS
    SELECT n.*,
           n.nm:first_name::VARCHAR                                                AS std_first_name,
           n.nm:last_name::VARCHAR                                                 AS std_lst_name,
           n.nm:full_name::VARCHAR                                                 AS std_full_name,
           n.nm:src_full_name::VARCHAR                                             AS std_src_full_name,
           n.nm:sfx_name::VARCHAR                                                  AS std_sfx_name,
           n.nm:src_suffix::VARCHAR                                                AS src_suffix,
           n.nm:suffix_exception_code::VARCHAR                                     AS suffix_exception_code,
           /* VALIDATION */
           NVL(LENGTH(TRIM(n.nm:first_name::VARCHAR)) > 0 AND LENGTH(TRIM(n.nm:last_name::VARCHAR)) > 0,
               FALSE)                                                              AS valid_member,
           IFF(fn_snow_helper03_common(n.nm:first_name::VARCHAR), 'Missing_First_Name', NULL) AS fn_missing_code,
           IFF(fn_snow_helper03_common(n.nm:last_name::VARCHAR), 'Missing_Last_Name', NULL)   AS ln_missing_code,
           n.REC_TYPE IN ('B', 'D')                                                AS end_dated
      FROM named n;
    SELECT COUNT(*) INTO :l_rows FROM WRK_CRE_CARE_S2_NAMED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'NAME_STANDARDISE_VALIDATE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_CRE_CARE_S2_NAMED', 'CREATED',
        'One standardised row per source record, with the valid-member flag (standardised first AND last name '
        || 'both present) and the end-dated flag for moved/deleted rows. Read by the rank step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 NAME_STANDARDISE_VALIDATE', :l_rows) || CHR(10);

    -- ---- Step 30: RANK + VALIDATION ENRICHMENT ---------------------------
    -- Purpose: one ranked row per CARE id (record type descending: I, D,
    -- B, A -- only the rank-1 row of a valid member loads), with the
    -- merge CARE id (the move target id for unmerged moves, else the
    -- CARE id itself), the blanked SSN, the translated state code, and
    -- every validation result: gender, ethnicity, race, standardised
    -- phone, CARE / Medicaid / SSN id checks, the US-vs-abroad flag, and
    -- the US address validation result.  Reads ONLY
    -- WRK_CRE_CARE_S2_NAMED (plus the reference lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_CRE_CARE_S3_RANKED AS
    WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_any  AS (SELECT * FROM TABLE(fn_snow_helper42_common())),
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
    -- SRT_VALID_MEMBERS + EXP_VALID_MEMBERS2 + LKP_INVALID_FIRSTNM / LASTNM + LKP_STATE_CODE
    ranked AS (
        SELECT m.*,
               /* TIMELINE: VERSION_SEQ_NUM per CARE id, REC_TYPE descending */
               IFF(m.valid_member,
                   ROW_NUMBER() OVER (PARTITION BY m.valid_member, m.CARE_ID ORDER BY m.REC_TYPE DESC), NULL)
                                                                                       AS version_seq_num,
               xf.EXCEPTION_CODE AS fn_exception_code, xf.EXCEPTION_DESC AS fn_exception_desc,
               xf.EXCEPTION_TYPE AS fn_exception_type,
               xl.EXCEPTION_CODE AS ln_exception_code, xl.EXCEPTION_DESC AS ln_exception_desc,
               xl.EXCEPTION_TYPE AS ln_exception_type,
               IFF(m.orig_rowid_object_desc = 'N', m.TARGET_ID, m.CARE_ID)             AS mrg_care_id,
               /* BAD DATA: SSN_OUT suppresses the default values */
               IFF(m.SSN = 'U' OR m.SSN = 'N', NULL, m.SSN)                            AS ssn_out,
               st.MSTR_CODE_VALUE                                                      AS std_state_cd
          FROM WRK_CRE_CARE_S2_NAMED m
          LEFT JOIN lkp_exc xf ON xf.EXCEPTION_CODE = m.fn_missing_code
          LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = m.ln_missing_code
          LEFT JOIN lkp_any st ON st.SRC_SYS = 'CRE' AND st.SRC_CODE_VALUE = m.STATE
    ),
    -- the mapplets and rules (only the de-duplicated members are routed to a target)
    dq AS (
        SELECT r.*,
               NVL(r.version_seq_num = 1, FALSE)                                       AS is_member,
               fn_snow_helper17_common(r.SEX, 'Indv', 'CRE')                           AS gd,
               et.MSTR_CODE_VALUE                                                      AS ethnicity_mstr,
               rc.MSTR_CODE_VALUE                                                      AS race_mstr,
               fn_snow_helper23_common(r.PHONE)                                        AS phone_std,
               fn_snow_helper37_common(r.mrg_care_id)                                  AS ci,
               fn_snow_helper27_common(r.RECIP_NO)                                     AS md,
               fn_snow_helper26_common(r.ssn_out)                                      AS sn,
               /* RTR_US_ADDRESSES.US_ADDRESSES: STD_STATE_CD <> '99' OR ISNULL(STD_STATE_CD) */
               NVL(r.std_state_cd <> '99', TRUE)                                       AS addr_us,
               ss.MSTR_CODE_VALUE                                                      AS source_state_fips
          FROM ranked r
          LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'CRE' AND et.SRC_CODE_VALUE = r.FEDETH
          LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'CRE' AND rc.SRC_CODE_VALUE = r.RACE
          LEFT JOIN lkp_cv ss ON ss.CODE_TYPE = 'STATE' AND ss.SRC_SYS = 'CRE'
                             AND ss.SRC_CODE_VALUE = UPPER(TRIM(r.STATE))
    )
    -- mplt_Global_Addr_Validation (US addresses) + rule_Phone_Std exception code
    SELECT d.*,
           IFF(d.addr_us, fn_snow_helper34_common(d.STREET, NULL, d.CITY, d.STATE,
                                                  NVL(d.ZIP, '') || '-' || NVL(d.ZIPSUF, ''), 'US',
                                                  d.source_state_fips), NULL) AS av,
           /* VALIDATION */
           fn_snow_helper24_common(d.phone_std, NULL, NULL, ar.NPA_ID, ar.SERVICE)  AS phone_code
      FROM dq d
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.phone_std, 1, 3);
    SELECT COUNT(*) INTO :l_rows FROM WRK_CRE_CARE_S3_RANKED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'RANK_ENRICH', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_CRE_CARE_S3_RANKED', 'CREATED',
        'Ranked rows per CARE id (record type descending) with gender, ethnicity, race, phone and alternate-id '
        || 'validation results and the US address validation result. Read by the flatten step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 RANK_ENRICH', :l_rows) || CHR(10);

    -- ---- Step 40: FLATTEN -- ADDRESS SPLIT + ALTERNATE-ID PREPARATION ----
    -- Purpose: load-ready rows.  The US-vs-abroad address split: US
    -- addresses use the validated address fields (a valid US address
    -- needs mailability score >= 3 or a match code not starting I / N,
    -- plus a state FIPS); abroad addresses use the source street/city
    -- with state 99 and country ZZ, and need city and street present.
    -- A bad address is logged instead of loaded (the member itself is
    -- still loaded).  Also built here: the phone key, the three
    -- alternate-id keys and values (CARE / Medicaid / SSN, with the
    -- type looked up by source value, no code-type filter), every
    -- exception code/description/type resolved from the exception
    -- lookup, and the timeline dates (end-dated 'B' / 'D' rows get
    -- start = last-update - 1 day, end = last-update, action 2).
    -- Reads ONLY WRK_CRE_CARE_S3_RANKED (plus the reference lookups).
    CREATE OR REPLACE TRANSIENT TABLE WRK_CRE_CARE_S4_FLAT AS
    WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_mc  AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
    -- lkp_ALT_ID_MSTR_REF_CODE: LOOKUP_CODE_VALUE of SRC_SYS CRE by source value (no code-type filter), any row
    alt_tp AS (
        SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE, l.MSTR_REF_LABEL, l.SRC_SYS
          FROM LOOKUP_CODE_VALUE l
         WHERE l.SRC_SYS = 'CRE' AND l.SRC_CODE_VALUE IN ('CARE ID', 'Medicaid ID', 'SSN')
       QUALIFY ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.CODE_TYPE) = 1
    )
    SELECT d.*,
           d.CARE_ID                                                               AS pty_key,
           NVL(d.CARE_ID, '') || '|' || :P_RLE_BO_CLASS_CD_MEMBER                  AS rle_key,
           NVL(d.CARE_ID, '') || '|Member'                                         AS member_rle_fk,
           /* TIMELINE: EXP_VALID_MEMBERS, EXP_PTY_HOLD / EXP_PTY_RLE_HOLD */
           IFF(d.end_dated, DATEADD(day, -1, d.CARE_LASTUP_DT), d.CARE_LASTUP_DT)  AS period_start,
           IFF(d.end_dated, d.CARE_LASTUP_DT, NULL)                                AS period_end,
           IFF(d.end_dated, 2, NULL)                                               AS timeline_action,
           IFF(d.end_dated, DATEADD(day, -1, d.CARE_LASTUP_DT), NULL)              AS period_reference_time,
           IFF(d.end_dated, DATEADD(hour, -1, :l_run_ts), :l_run_ts)               AS last_update,
           IFF(d.end_dated, DATEADD(day, 1, DATEADD(day, -1, d.CARE_LASTUP_DT)), NULL) AS pty_period_end,
           IFF(d.end_dated, DATEADD(day, -1, d.CARE_LASTUP_DT), NULL)              AS pty_period_reference_time,
           NVL(d.CARE_LASTUP_DT, d.INSERT_DATE)                                    AS src_last_update,
           d.gd:mdm_gender_code::VARCHAR                                           AS mdm_gender_code,
           d.gd:exception_code::VARCHAR                                            AS gender_exception_code,
           xg.EXCEPTION_DESC                                                       AS gender_exception_description,
           xg.EXCEPTION_TYPE                                                       AS gender_exception_type,
           xs.EXCEPTION_DESC                                                       AS suffix_exception_desc,
           xs.EXCEPTION_TYPE                                                       AS suffix_exception_type,
           xe.EXCEPTION_CODE AS ethnicity_exception_code, xe.EXCEPTION_DESC AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE AS ethnicity_exception_type,
           xr.EXCEPTION_CODE AS race_exception_code, xr.EXCEPTION_DESC AS race_exception_desc,
           xr.EXCEPTION_TYPE AS race_exception_type,
           xp.EXCEPTION_CODE AS phone_exception_code, xp.EXCEPTION_DESC AS phone_exception_desc,
           xp.EXCEPTION_TYPE AS phone_exception_type,
           NVL(d.CARE_ID, '') || '|Member|Telephone|001|' || NVL(d.phone_std, '')  AS phn_key,
           /* VALIDATION: RTR_VALID_ADDRESS / RTR_VALID_NON_US_ADDRESSES */
           IFF(d.addr_us,
               NVL((TRUNC(TRY_TO_NUMBER(d.av:mailability_score::VARCHAR)) >= 3
                    OR LEFT(d.av:match_code::VARCHAR, 1) NOT IN ('I', 'N'))
                   AND d.av:state_fips_cd::VARCHAR IS NOT NULL, FALSE),
               d.CITY IS NOT NULL AND d.STREET IS NOT NULL)                       AS addr_valid,
           IFF(d.addr_us, d.av:delivery_address_line1::VARCHAR, INITCAP(d.STREET)) AS a_line1,
           IFF(d.addr_us, d.av:delivery_address_line2::VARCHAR, NULL)             AS a_line2,
           IFF(d.addr_us, d.av:city::VARCHAR, INITCAP(d.CITY))                    AS a_city,
           IFF(d.addr_us, d.av:state_fips_cd::VARCHAR, :P_DEFAULT_NONUS_STATE_CD) AS a_state,
           IFF(d.addr_us, d.av:county_fips_cd::VARCHAR, d.CNTY)                   AS a_county_fips,
           IFF(d.addr_us, d.av:country_iso2_char::VARCHAR, 'ZZ')                  AS a_country,
           IFF(d.addr_us, d.av:zip_cd_5::VARCHAR, d.ZIP)                          AS a_postcode,
           IFF(d.addr_us, d.av:zip_cd_4_extn::VARCHAR, d.ZIPSUF)                  AS a_postcode_ext,
           d.av:geocoding_latitude::NUMBER(38, 6)                                  AS a_latitude,
           d.av:geocoding_longitude::NUMBER(38, 6)                                 AS a_longitude,
           d.av:mailability_score::VARCHAR                                         AS a_mailability_score,
           d.av:match_code::VARCHAR                                                AS a_match_code,
           d.av:address_type::VARCHAR                                              AS a_address_type,
           d.av:sub_building_number::VARCHAR                                       AS a_sub_building_number,
           d.av:sub_building_descriptor::VARCHAR                                   AS a_sub_building_descriptor,
           d.av:sub_building_complete::VARCHAR                                     AS a_sub_building_complete,
           d.av:building_number::VARCHAR                                           AS a_building_number,
           d.av:building_name::VARCHAR                                             AS a_building_name,
           d.av:residential_delivery_indicator::VARCHAR                           AS a_residential,
           d.av:geocoding_status::VARCHAR                                          AS a_geocoding_status,
           d.av:organization_name::VARCHAR                                         AS a_org_name,
           d.av:organization_descriptor::VARCHAR                                   AS a_org_descriptor,
           TRY_TO_NUMBER(d.av:mailability_score::VARCHAR)                          AS a_dr_mailability_score,
           mc.DESCRIPTION                                                          AS a_dr_error_desc,
           d.av:match_code::VARCHAR                                                AS a_dr_error_code,
           NVL(d.STREET, '') || ' ' || '' || ' ' || NVL(d.CITY, '') || ' ' || NVL(d.STATE, '') || ' '
           || NVL(d.ZIP, '')                                                       AS addr_attribute_value,
           xa.EXCEPTION_CODE AS addr_exception_code, xa.EXCEPTION_DESC AS addr_exception_desc,
           xa.EXCEPTION_TYPE AS addr_exception_type,
           -- NRML_ALT_ID occurrences and lkp_ALT_ID_MSTR_REF_CODE
           d.ci:id_value::VARCHAR                                                  AS care_alt_id,
           t1.MSTR_REF_CODE                                                        AS care_tp_cd,
           d.md:id_value::VARCHAR                                                  AS medicaid_alt_id,
           d.md:exception_code::VARCHAR                                            AS medicaid_exception_code,
           xm.EXCEPTION_DESC AS medicaid_exception_desc, xm.EXCEPTION_TYPE AS medicaid_exception_type,
           t2.MSTR_REF_CODE AS medicaid_tp_cd, t2.MSTR_REF_LABEL AS medicaid_tp_lbl,
           t2.SRC_SYS AS medicaid_tp_sys,
           /* VALIDATION: exp_validate_ssn + Lkp_EXC_LOOKUP_CODE_VALUE_SSN (looked-up code) */
           xn.EXCEPTION_CODE AS ssn_exception_code, xn.EXCEPTION_DESC AS ssn_exception_desc,
           xn.EXCEPTION_TYPE AS ssn_exception_type,
           t3.MSTR_REF_CODE AS ssn_tp_cd, t3.MSTR_REF_LABEL AS ssn_tp_lbl, t3.SRC_SYS AS ssn_tp_sys
      FROM WRK_CRE_CARE_S3_RANKED d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
      LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.suffix_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = d.phone_code
      LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = d.md:exception_code::VARCHAR
      LEFT JOIN lkp_exc xn ON xn.EXCEPTION_CODE = IFF(d.sn:ssn_status::VARCHAR = 'Invalid'
                                                      AND d.ssn_out IS NOT NULL, 'Invalid_SSN', NULL)
      LEFT JOIN lkp_exc xa ON xa.EXCEPTION_CODE = 'Invalid_Address'
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = d.av:match_code::VARCHAR
      LEFT JOIN alt_tp t1 ON t1.SRC_CODE_VALUE = 'CARE ID'
      LEFT JOIN alt_tp t2 ON t2.SRC_CODE_VALUE = 'Medicaid ID'
      LEFT JOIN alt_tp t3 ON t3.SRC_CODE_VALUE = 'SSN';
    SELECT COUNT(*) INTO :l_rows FROM WRK_CRE_CARE_S4_FLAT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'FLAT_ADDR_ALTID', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_CRE_CARE_S4_FLAT', 'CREATED',
        'Flattened load-ready rows: US vs abroad address split with validated or fallback fields, phone key, '
        || 'alternate-id keys and values, exception codes and timeline dates. Read by the keying step.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 FLAT_ADDR_ALTID', :l_rows) || CHR(10);

    -- ---- Step 50: KEYING -- ROUTES + UNIQUE-KEY GUARDS --------------------
    -- Purpose: the rows the publish step writes, with the county rule
    -- (non-Texas state -> 996, missing county FIPS -> 998, else the
    -- county FIPS), the address / phone / alternate-id keys, the route
    -- flag for every target and exception class (every flag NVL'd: a
    -- NULL router condition does not route), the run constants, the
    -- SRC_ROWIDs cut to 30 characters, and the insert-only guards:
    -- keys already in a target (VERSION_SEQ = 1) are skipped, and the
    -- first row per exception key wins (record type descending).
    -- Reads ONLY WRK_CRE_CARE_S4_FLAT.
    CREATE OR REPLACE TRANSIENT TABLE WRK_CRE_CARE_S5_KEYED AS
    WITH
    keyed AS (
        SELECT f.*,
               /* EXP_PTY_RLE_ADDR_HOLD.out_COUNTY_CD */
               CASE WHEN f.a_state <> :P_DEFAULT_TX_STATE_CD THEN :P_COUNTY_CD_NONTX
                    WHEN f.a_county_fips IS NULL THEN :P_COUNTYCD_DEFAULTALL
                    ELSE f.a_county_fips END                                           AS a_county,
               f.rle_key || '|' || :P_PHYSICAL_ADDR_TYPE_CD                            AS addr_key,
               IFF(f.care_alt_id IN ('U', 'N'), NULL, f.care_alt_id)                   AS care_alt_val,
               IFF(f.medicaid_alt_id IN ('U', 'N'), NULL, f.medicaid_alt_id)           AS medicaid_alt_val,
               f.rle_key || '|' || NVL(f.care_tp_cd, '') || '|' || NVL(f.care_alt_id, '')         AS care_alt_key,
               f.rle_key || '|' || NVL(f.medicaid_tp_cd, '') || '|' || NVL(f.medicaid_alt_id, '') AS medicaid_alt_key,
               f.rle_key || '|' || NVL(f.ssn_tp_cd, '') || '|' || NVL(f.ssn_out, '')              AS ssn_alt_key,
               /* routes (every flag NVL'd: a NULL router condition does not route) */
               NOT f.grp_deletes AND NVL(f.orig_rowid_object_desc = 'N', FALSE)        AS grp_mrg,
               NOT f.valid_member AND (f.fn_exception_code IS NOT NULL OR f.fn_exception_desc IS NOT NULL
                                       OR f.fn_exception_type IS NOT NULL)            AS grp_first_name,
               NOT f.valid_member AND (f.ln_exception_code IS NOT NULL OR f.ln_exception_desc IS NOT NULL
                                       OR f.ln_exception_type IS NOT NULL)            AS grp_last_name,
               f.is_member AND f.gender_exception_description IS NOT NULL              AS grp_gender,
               f.is_member AND f.suffix_exception_code IS NOT NULL                     AS grp_suffix,
               f.is_member AND f.ethnicity_exception_code IS NOT NULL                  AS grp_ethnicity,
               f.is_member AND f.race_exception_code IS NOT NULL                       AS grp_race,
               f.is_member AND f.addr_valid                                            AS grp_addr,
               f.is_member AND NOT f.addr_valid                                        AS grp_addr_exc,
               f.is_member AND f.PHONE IS NOT NULL AND f.phone_exception_code IS NULL  AS grp_phone,
               f.is_member AND f.PHONE IS NOT NULL AND f.phone_exception_code IS NOT NULL AS grp_phone_exc,
               f.is_member AND f.care_alt_id IS NOT NULL                               AS grp_care_alt,
               f.is_member AND f.medicaid_alt_id IS NOT NULL AND f.medicaid_exception_code IS NULL
                                                                                       AS grp_medicaid_alt,
               f.is_member AND f.medicaid_alt_id IS NOT NULL AND f.medicaid_exception_code IS NOT NULL
                                                                                       AS grp_medicaid_exc,
               f.is_member AND f.ssn_out IS NOT NULL AND f.ssn_exception_code IS NULL  AS grp_ssn_alt,
               f.is_member AND f.ssn_out IS NOT NULL AND f.ssn_exception_code IS NOT NULL AS grp_ssn_exc
          FROM WRK_CRE_CARE_S4_FLAT f
    )
    SELECT k.*,
           'CRE'                                             AS src_sys,
           :l_run_ts                                         AS run_ts,
           :c_mapping                                        AS mapping_name,
           'Indv'                                            AS pty_bo_class_cd,
           :P_RLE_BO_CLASS_CD_MEMBER                         AS rle_bo_class_cd,
           :P_PHYSICAL_ADDR_TYPE_CD                          AS addr_tp,
           'Payer'                                           AS hierarchy_code,
           'Primary'                                         AS pref_lvl,
           'Member Addr'                                     AS hm_rel_tp_cd,
           'US'                                              AS src_cntry,
           'Telephone'                                       AS phn_tp,
           '001'                                             AS usg_tp_phone,
           'Issued'                                          AS sts_cd,
           'First Name'                                      AS attr_first_name,
           'Last Name'                                       AS attr_last_name,
           'Gender'                                          AS attr_gender,
           'Name Suffix'                                     AS attr_suffix,
           'FEDETH'                                          AS attr_fedeth,
           'RACE'                                            AS attr_race,
           'Address'                                         AS attr_address,
           'Telephone'                                       AS attr_phone,
           CAST(NULL AS TIMESTAMP_NTZ)                       AS null_timestamp,   -- TIMELINE: not linked
           CAST(NULL AS NUMBER)                              AS null_number,      -- TIMELINE: not linked
           /* BAD DATA: SRC_ROWID is 30 characters */
           LEFT(k.addr_key, 30)                              AS addr_src_rowid,
           LEFT(k.phn_key, 30)                               AS phn_src_rowid,
           LEFT(k.care_alt_key, 30)                          AS care_alt_src_rowid,
           LEFT(k.medicaid_alt_key, 30)                      AS medicaid_alt_src_rowid,
           LEFT(k.ssn_alt_key, 30)                           AS ssn_alt_src_rowid,
           /* BAD DATA: unique keys Snowflake does not enforce */
           ROW_NUMBER() OVER (PARTITION BY k.grp_first_name, k.CARE_ID, k.fn_exception_type, k.fn_exception_code
                              ORDER BY k.REC_TYPE DESC) = 1  AS uq_first_name,
           ROW_NUMBER() OVER (PARTITION BY k.grp_last_name, k.CARE_ID, k.ln_exception_type, k.ln_exception_code
                              ORDER BY k.REC_TYPE DESC) = 1  AS uq_last_name,
           xpty.PKEY_SRC_OBJECT IS NULL                      AS uq_pty,
           xrle.PKEY_SRC_OBJECT IS NULL                      AS uq_rle,
           xadr.PKEY_SRC_OBJECT IS NULL                      AS uq_addr,
           xphn.PKEY_SRC_OBJECT IS NULL                      AS uq_phone,
           xca.PKEY_SRC_OBJECT IS NULL                       AS uq_care_alt,
           xma.PKEY_SRC_OBJECT IS NULL                       AS uq_medicaid_alt,
           xsa.PKEY_SRC_OBJECT IS NULL                       AS uq_ssn_alt,
           ROW_NUMBER() OVER (PARTITION BY k.grp_medicaid_exc, k.mrg_care_id, k.medicaid_exception_type,
                                           k.medicaid_exception_code ORDER BY k.REC_TYPE DESC) = 1
                                                             AS uq_medicaid_exc,
           ROW_NUMBER() OVER (PARTITION BY k.grp_ssn_exc, k.mrg_care_id, k.ssn_exception_type,
                                           k.ssn_exception_code ORDER BY k.REC_TYPE DESC) = 1
                                                             AS uq_ssn_exc
      FROM keyed k
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY WHERE VERSION_SEQ = 1) xpty
             ON xpty.PKEY_SRC_OBJECT = k.pty_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE WHERE VERSION_SEQ = 1) xrle
             ON xrle.PKEY_SRC_OBJECT = k.rle_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xadr
             ON xadr.PKEY_SRC_OBJECT = k.addr_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xphn
             ON xphn.PKEY_SRC_OBJECT = k.phn_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xca
             ON xca.PKEY_SRC_OBJECT = k.care_alt_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xma
             ON xma.PKEY_SRC_OBJECT = k.medicaid_alt_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xsa
             ON xsa.PKEY_SRC_OBJECT = k.ssn_alt_key;
    SELECT COUNT(*) INTO :l_rows FROM WRK_CRE_CARE_S5_KEYED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'KEYED_ROUTES_GUARDS', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_CRE_CARE_S5_KEYED', 'CREATED',
        'Routed rows with route flags for every target and exception class, run constants, SRC_ROWIDs cut to 30 '
        || 'characters, and insert-only unique-key guards against existing targets. Read by the publish step.',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 KEYED_ROUTES_GUARDS', :l_rows) || CHR(10);

    -- ---- Step 60: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-50 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning.  The eighteen INSERTs below are
    -- the eighteen branches of the original INSERT ALL, in the same
    -- order, with the same column lists, values and WHERE conditions --
    -- only the source changed, from the final select to step 50.
    BEGIN TRANSACTION;
    -- 60a. RTR_MERGES.Default -> FLTR_CRE_MRG -> Write_CRE_SRC_MRG
    INSERT INTO CRE_SRC_MRG (SRC_ROWID_OBJECT, TGT_ROWID_OBJECT, RUN_DATE)
    SELECT src_rowid_object, tgt_rowid_object, run_ts
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_mrg;
    -- 60b. rtr_Invalid_First_Last_Name.FirstName_Issue -> Write_EXC_STG_BAD_REC_MEMB_FName
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_1, RUN_DATE, MAPPING_NAME, FIRST_NAME, LAST_NAME, ATTRIBUTE_NAME, GENDER, BIRTH_DATE,
            SUFFIX, SRC_SYS, ATTRIBUTE_VALUE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
    SELECT CARE_ID, run_ts, mapping_name, std_first_name, std_lst_name, attr_first_name, SEX, BIRTH_DT,
           std_sfx_name, src_sys, FIRSTNM, fn_exception_type, fn_exception_desc, fn_exception_code
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_first_name AND uq_first_name;
    -- 60c. rtr_Invalid_First_Last_Name.LastName_Issue -> exp_Last_Name_Exception -> Write_EXC_STG_BAD_REC_MEMB_LName
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, FIRST_NAME, MAPPING_NAME, BIRTH_DATE, GENDER, ADDRESS_LINE_1,
            ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ATTRIBUTE_NAME, LAST_NAME,
            SUFFIX, ATTRIBUTE_VALUE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT src_sys, CARE_ID, run_ts, std_first_name, mapping_name, BIRTH_DT, SEX, STREET, CITY, CNTY, STATE,
           ZIP, ZIPSUF, attr_last_name, std_lst_name, std_sfx_name, LASTNM, ln_exception_code,
           ln_exception_desc, ln_exception_type
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_last_name AND uq_last_name;
    -- 60d. Filt_DeDeup_Seq1 -> EXP_PTY -> EXP_PTY_HOLD -> SRT_MRG_RECORDS -> Write_C_S_CRE_PTY
    INSERT INTO C_S_CRE_PTY
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, BIRTH_DT, FULL_NM, GNDR_CD, SFX_NM,
            LST_NM, FRST_NM, PTY_BO_CLASS_CD, SRC_FULL_NM, SRC_LAST_UPD_DT, ETHNCTY, RACE_CD, SRC_ETHNCTY,
            SRC_RACE_CD)
    SELECT pty_key, period_start, pty_period_end, version_seq_num, pty_period_reference_time,
           timeline_action, last_update, last_update, pty_key, BIRTH_DT, std_full_name, mdm_gender_code,
           std_sfx_name, std_lst_name, std_first_name, pty_bo_class_cd, std_src_full_name, src_last_update,
           ethnicity_mstr, race_mstr, FEDETH, RACE
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE is_member AND uq_pty;
    -- 60e. EXP_PTY_RLE_HOLD -> Write_C_S_CRE_PTY_RLE
    INSERT INTO C_S_CRE_PTY_RLE
           (PTY_FK, PKEY_SRC_OBJECT, SRC_ROWID, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ,
            LAST_UPDATE_DATE, RLE_BO_CLASS_CD, CREATE_DATE, SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION)
    SELECT pty_key, rle_key, rle_key, period_start, pty_period_end, version_seq_num, run_ts,
           rle_bo_class_cd, run_ts, src_last_update, null_timestamp, null_number
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE is_member AND uq_rle;
    -- 60f. fltr_Gender_Exc -> Exp_Write_Gender_Exc -> Write_EXC_STG_BAD_REC_MEMB_Gender_Cd
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
            EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC)
    SELECT src_sys, CARE_ID, run_ts, SEX, attr_gender, SEX, mapping_name, gender_exception_type,
           gender_exception_code, gender_exception_description
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_gender;
    -- 60g. fltr_Suffix_exc -> Exp_Write_Suffix_Exc -> Write_EXC_STG_BAD_REC_MEMB_Suffix
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, MAPPING_NAME)
    SELECT src_sys, CARE_ID, suffix_exception_type, suffix_exception_code, suffix_exception_desc, run_ts,
           attr_suffix, src_suffix, mapping_name
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_suffix;
    -- 60h. Filt_Bad_Ethnicity_Cd -> Write_EXC_STG_BAD_REC_MEMB_Ethnicity_Cd
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, EXCEPTION_CODE,
            EXCEPTION_TYPE, EXCEPTION_DESC)
    SELECT src_sys, pty_key, run_ts, attr_fedeth, FEDETH, mapping_name, ethnicity_exception_code,
           ethnicity_exception_type, ethnicity_exception_desc
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_ethnicity;
    -- 60i. Filt_Bad_Race_Cd -> Write_EXC_STG_BAD_REC_MEMB_Race_Cd
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, EXCEPTION_TYPE,
            EXCEPTION_DESC, EXCEPTION_CODE)
    SELECT src_sys, pty_key, run_ts, attr_race, RACE, mapping_name, race_exception_type, race_exception_desc,
           race_exception_code
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_race;
    -- 60j. UNION_ADDRESSES -> EXP_PTY_RLE_ADDR_HOLD -> Write_C_S_CRE_PTY_RLE_ADDR
    INSERT INTO C_S_CRE_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, LAST_UPDATE_DATE, PERIOD_START_DATE, PERIOD_END_DATE,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, CREATE_DATE, HIERARCHY_CODE, PREF_LVL, ADDR_TP, HM_REL_TP_CD,
            ADDR_LN_1, ADDR_LN_2, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD, LNGTD, MLBLTY_SCR,
            PTY_RLE_FK, USG_TP, SRC_ADDR_LN_1, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD,
            SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, FLR_NUM, ADDR_TP_CD, SUB_BLDG_DESC, SUB_BLDG_NM, BLDG_NMBR,
            BLDNG_NM, RSDNTL_DLVRY_IND, GEOCD_STS_CD, ORG_NM, ORG_DESC, VLDTN_MSG)
    SELECT addr_key, addr_src_rowid, version_seq_num, last_update, period_start, period_end,
           period_reference_time, timeline_action, last_update, hierarchy_code, pref_lvl, addr_tp,
           hm_rel_tp_cd, a_line1, a_line2, a_city, a_county, a_state, a_country, a_postcode, a_postcode_ext,
           a_latitude, a_longitude, a_mailability_score, rle_key, addr_tp, STREET, CITY, CNTY, STATE,
           src_cntry, ZIP, ZIPSUF, CARE_LASTUP_DT, a_sub_building_number, a_address_type,
           a_sub_building_descriptor, a_sub_building_complete, a_building_number, a_building_name,
           a_residential, a_geocoding_status, a_org_name, a_org_descriptor, a_match_code
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_addr AND uq_addr;
    -- 60k. UNION_INVALID_ADDRESSES -> Lkp_EXC_LOOKUP_CODE_VALUE -> Write_EXC_STG_BAD_REC_MEMB_ADDR
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, MAPPING_NAME, ADDRESS_DR_MAILABILITY_SCORE, ADDRESS_DR_ERROR_DESC,
            ADDRESS_DR_ERROR_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1, ADDRESS_LINE_1, ADDRESS_CITY,
            ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT src_sys, run_ts, mapping_name, a_dr_mailability_score, a_dr_error_desc, a_dr_error_code,
           attr_address, addr_attribute_value, CARE_ID, STREET, CITY, CNTY, STATE, ZIP, ZIPSUF, src_cntry,
           addr_exception_code, addr_exception_desc, addr_exception_type
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_addr_exc;
    -- 60l. RTR_VALID_PHONE.VALID -> EXP_PTY_RLE_PHN_HOLD -> Write_C_S_CRE_PTY_RLE_PHN
    INSERT INTO C_S_CRE_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, SRC_ROWID, PHN_NUM, VERSION_SEQ, LAST_UPDATE_DATE, PHN_TP, PTY_RLE_FK, USG_TP,
            PREF_LVL, PERIOD_START_DATE, PERIOD_END_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, CREATE_DATE,
            SRC_LAST_UPD_DT)
    SELECT phn_key, phn_src_rowid, phone_std, version_seq_num, last_update, phn_tp, member_rle_fk,
           usg_tp_phone, pref_lvl, period_start, period_end, timeline_action, period_reference_time,
           last_update, CARE_LASTUP_DT
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_phone AND uq_phone;
    -- 60m. RTR_VALID_PHONE.Default -> EXP_PTY_RLE_PHN_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_PHONE
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, PRIMARY_PHONE, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1,
            EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC)
    SELECT src_sys, phone_std, mapping_name, run_ts, attr_phone, phone_std, CARE_ID, phone_exception_code,
           phone_exception_type, phone_exception_desc
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_phone_exc;
    -- 60n. NRML_ALT_ID CARE ID -> RTR_VALID_ALT_ID.VALID_ALT_ID -> EXP_ALT_ID_SET_PKEY -> Write_C_S_CRE_PTY_RLE_ALT_ID
    INSERT INTO C_S_CRE_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
            ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION)
    SELECT care_alt_key, period_start, period_end, version_seq_num, rle_key, care_tp_cd, care_alt_val,
           care_tp_cd, sts_cd, care_alt_src_rowid, CARE_LASTUP_DT, last_update, null_timestamp, null_number
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_care_alt AND uq_care_alt;
    -- 60o. NRML_ALT_ID Medicaid ID -> VALID_ALT_ID
    INSERT INTO C_S_CRE_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
            ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION)
    SELECT medicaid_alt_key, period_start, period_end, version_seq_num, rle_key, medicaid_tp_cd,
           medicaid_alt_val, medicaid_tp_cd, sts_cd, medicaid_alt_src_rowid, CARE_LASTUP_DT, last_update,
           null_timestamp, null_number
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_medicaid_alt AND uq_medicaid_alt;
    -- 60p. NRML_ALT_ID Medicaid ID -> RTR_VALID_ALT_ID.Default -> EXP_ALT_ID_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_ALT_ID
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE,
            ATTRIBUTE_VALUE, SRC_SYS_ID_1)
    SELECT mapping_name, run_ts, medicaid_tp_lbl, medicaid_tp_sys, medicaid_exception_code,
           medicaid_exception_desc, medicaid_exception_type, medicaid_alt_id, mrg_care_id
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_medicaid_exc AND uq_medicaid_exc;
    -- 60q. NRML_ALT_ID SSN -> VALID_ALT_ID
    INSERT INTO C_S_CRE_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
            ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION)
    SELECT ssn_alt_key, period_start, period_end, version_seq_num, rle_key, ssn_tp_cd, ssn_out, ssn_tp_cd,
           sts_cd, ssn_alt_src_rowid, CARE_LASTUP_DT, last_update, null_timestamp, null_number
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_ssn_alt AND uq_ssn_alt;
    -- 60r. NRML_ALT_ID SSN -> RTR_VALID_ALT_ID.Default -> EXP_ALT_ID_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_ALT_ID
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE,
            ATTRIBUTE_VALUE, SRC_SYS_ID_1)
    SELECT mapping_name, run_ts, ssn_tp_lbl, ssn_tp_sys, ssn_exception_code, ssn_exception_desc,
           ssn_exception_type, ssn_out, mrg_care_id
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_ssn_exc AND uq_ssn_exc;
    COMMIT;
    -- Publish headline count: members selected to load (is_member).
    -- Merge rows and exception rows are counted by the step-10 / step-50
    -- checkpoints; each INSERT above uses its own original WHEN guard.
    SELECT COUNT(*) INTO :l_rows FROM WRK_CRE_CARE_S5_KEYED WHERE is_member;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'PUBLISH', 'COMPLETED',
        'CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN, C_S_CRE_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE',
        'Published in one transaction: merge rows, parties, roles, addresses, phones, alternate ids and all exception classes. '
        || 'Count shown is members selected to load (is_member); see the step-10/50 counts for merge and exception inputs.',
        NULL, 'Step 60 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 PUBLISH (members)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_CRE_CARE_Clients completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_CRE_CARE_Clients failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
