-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Addr_1  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_TRS_Addr_1, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Business requirement (see TRS_IDQ_Business_Requirements_Notes.md):
--   BR-31  Validate unique addresses once, then distribute.  This is
--          step 1: every UNIQUE address of the daily extract goes
--          through the address validator once (about a tenth of the
--          volume), and every result, good or bad, is written to the
--          intermediate table STG_TRS_D_UNQ_ADDR.  Addr_2 joins it back
--          to the individuals.
--   BR-32  Addresses are certified US addresses (AddressDoctor, USA
--          only, pre/post-scrub, state/county defaults).  In Snowflake
--          the validator is a pass-through stand-in (see Parity notes).
--   BR-33  Only fully scored addresses load in Addr_2; the score itself
--          is computed there, not here.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT statement, one CTE chain (src -> derived ->
--   validated -> final SELECT with the match-code lookup, the
--   already-validated guard and the per-ADDR_ID rank), one transaction,
--   one log line at the end.  If it failed, nothing told you which
--   logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT, written as a single
--   INSERT from the last work table inside ONE transaction.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_TRS_ADDR1_S10_SRC       distinct addresses from the extract
--   Step 20  WRK_TRS_ADDR1_S20_DERIVED   street-type lookup + derived lines 1/2
--   Step 30  WRK_TRS_ADDR1_S30_VALIDATED address validation (pass-through) + state lookup
--   Step 40  WRK_TRS_ADDR1_S40_READY     match-code description, already-validated
--                                        guard, one row per ADDR_ID
--   Step 50  PUBLISH                    STG_TRS_D_UNQ_ADDR, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT -- see the User Guide, "Boundaries")
--   WRK_TRS_ADDR1_S10_SRC, WRK_TRS_ADDR1_S20_DERIVED,
--   WRK_TRS_ADDR1_S30_VALIDATED, WRK_TRS_ADDR1_S40_READY.  They live in
--   the same schema as the targets (unqualified names, as in the
--   original code), are prefixed WRK_TRS_, and are registered in
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
--     DELETE of targets.  IDQ truncates STG_TRS_D_UNQ_ADDR first; the
--     Snowflake version instead skips addresses already present (the
--     xu guard in step 40), so an address validated in an earlier run
--     is not written again and is re-used by Addr_2.  A re-run therefore
--     inserts nothing twice, but it also does not remove rows that IDQ
--     would have truncated away -- see the User Guide, "Parity gaps".
--   * The address validator is a pass-through stand-in for AddressDoctor
--     (fn_snow_helper34_common, with its state-code and match-code
--     lookups).  It does not certify addresses the way AddressDoctor
--     does; the score is computed later, in Addr_2.
--   * SRC_COUNTY is NULL (unfed port), as in the original.  The scrub
--     rules clean the result lines; the derived source lines are kept
--     in SRC_ADDR_LN_*.
--   * STG_TRS_D_UNQ_ADDR has primary key ADDR_ID, which Snowflake does
--     not enforce; the step-40 guard (not already in the table, first
--     row per ADDR_ID in this run) is what prevents duplicates.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Addr_1 (
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
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Addr_1';
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
    DROP TABLE IF EXISTS WRK_TRS_ADDR1_S10_SRC;
    DROP TABLE IF EXISTS WRK_TRS_ADDR1_S20_DERIVED;
    DROP TABLE IF EXISTS WRK_TRS_ADDR1_S30_VALIDATED;
    DROP TABLE IF EXISTS WRK_TRS_ADDR1_S40_READY;


    -- ---- Step 10: DISTINCT ADDRESSES FROM THE EXTRACT (BR-31) -----------
    -- Purpose: one row per unique address in the daily extract, keyed by
    -- the address parts (street number, fraction, name, direction, type,
    -- dwelling type, apartment, line, city, state, zip5, zip4).  This is
    -- the volume reduction that makes address validation affordable:
    -- only unique addresses are validated, not one row per member.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR1_S10_SRC AS
    SELECT DISTINCT
           NVL(TO_VARCHAR(a.addr_st_num), '') || '|' || NVL(a.addr_st_num_frac, '') || '|' || NVL(a.addr_st_nm, '')
           || '|' || NVL(a.addr_st_dir_cd, '') || '|' || NVL(a.addr_st_type_cd, '') || '|'
           || NVL(a.addr_dwelling_type_cd, '') || '|' || NVL(a.addr_apt_num, '') || '|' || NVL(a.addr_line, '')
           || '|' || NVL(a.addr_city, '') || '|' || NVL(a.addr_state_cd, '') || '|' || NVL(TO_VARCHAR(a.addr_zip5), '')
           || '|' || NVL(TO_VARCHAR(a.addr_zip4), '')                                   AS ADDR_ID,
           a.addr_st_num AS ADDR_ST_NUM, a.addr_st_num_frac AS ADDR_ST_NUM_FRAC, a.addr_st_nm AS ADDR_ST_NM,
           a.addr_apt_num AS ADDR_APT_NUM, a.addr_line AS ADDR_LINE, a.addr_city AS ADDR_CITY,
           a.addr_state_cd AS ADDR_STATE_CD, a.addr_zip5 AS ADDR_ZIP5, a.addr_zip4 AS ADDR_ZIP4,
           a.addr_dwelling_type_cd AS ADDR_DWELLING_TYPE_CD, a.addr_st_type_cd AS ADDR_ST_TYPE_CD,
           a.addr_st_dir_cd AS ADDR_ST_DIR_CD
      FROM STG_TRS_D_INDV_ADDR a;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR1_S10_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_DISTINCT_ADDR', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR1_S10_SRC', 'CREATED',
        'Distinct addresses from the daily extract, keyed by address parts (BR-31). '
        || 'Read by the derivation step; the raw extract is not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_DISTINCT_ADDR', :l_rows) || CHR(10);

    -- ---- Step 20: STREET-TYPE LOOKUP + DERIVED LINES --------------------
    -- Purpose: lkp_Addr_Street_Type (STG_TRS_CD_REF) plus
    -- exp_TRS_Addr_Derivation.  Line 1 = street number, fraction,
    -- direction (EA/NO/SO/WE abbreviated to the first letter, any case),
    -- street name, street type description.  Line 2 = dwelling type,
    -- apartment number, address line.  Reads ONLY step 10.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR1_S20_DERIVED AS
    SELECT s.*,
           TRIM(NVL(TO_VARCHAR(s.ADDR_ST_NUM), '') || ' ' || NVL(s.ADDR_ST_NUM_FRAC, '') || ' '
                || NVL(IFF(UPPER(s.ADDR_ST_DIR_CD) IN ('EA', 'NO', 'SO', 'WE'), SUBSTR(s.ADDR_ST_DIR_CD, 1, 1),
                           s.ADDR_ST_DIR_CD), '')
                || ' ' || NVL(s.ADDR_ST_NM, '') || ' ' || NVL(st.DESCRIPTION, ''))                AS addr_line_1,
           TRIM(NVL(s.ADDR_DWELLING_TYPE_CD, '') || ' ' || NVL(s.ADDR_APT_NUM, '') || ' '
                || NVL(s.ADDR_LINE, ''))                                                         AS addr_line_2
      FROM WRK_TRS_ADDR1_S10_SRC s
      LEFT JOIN (SELECT r.CODE, r.DESCRIPTION FROM STG_TRS_CD_REF r
                 QUALIFY ROW_NUMBER() OVER (PARTITION BY r.CODE ORDER BY r.DESCRIPTION) = 1) st
             ON st.CODE = s.ADDR_ST_TYPE_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR1_S20_DERIVED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'DERIVED_ADDR_LINES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR1_S20_DERIVED', 'CREATED',
        'Derived address lines 1 and 2, with the street-type description looked up (BR-31). '
        || 'Read by the validation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 DERIVED_ADDR_LINES', :l_rows) || CHR(10);

    -- ---- Step 30: ADDRESS VALIDATION (BR-32) ----------------------------
    -- Purpose: mplt_Global_Addr_Validation (fn_snow_helper34_common, with
    -- its lkp_State_Cd and lkp_ref_MatchCode_Desc).  Zip is passed as
    -- zip5 || '-' || zip4; country is 'US'.  The validator result is
    -- kept as one structured value (av) and unpacked in step 40, exactly
    -- as the original did.  Reads ONLY step 20.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR1_S30_VALIDATED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT d.*,
           fn_snow_helper34_common(d.addr_line_1, d.addr_line_2, d.ADDR_CITY, d.ADDR_STATE_CD,
                                   NVL(TO_VARCHAR(d.ADDR_ZIP5), '') || '-' || NVL(TO_VARCHAR(d.ADDR_ZIP4), ''),
                                   'US', stc.MSTR_CODE_VALUE) AS av
      FROM WRK_TRS_ADDR1_S20_DERIVED d
      LEFT JOIN lkp_cv stc ON stc.CODE_TYPE = 'STATE' AND stc.SRC_SYS = 'TRS'
                          AND stc.SRC_CODE_VALUE = UPPER(TRIM(d.ADDR_STATE_CD));
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR1_S30_VALIDATED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ADDR_VALIDATION', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_TRS_ADDR1_S30_VALIDATED', 'CREATED',
        'Validated addresses (pass-through stand-in for AddressDoctor, BR-32). '
        || 'Read by the ready step; the score is computed in Addr_2, not here.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ADDR_VALIDATION', :l_rows) || CHR(10);

    -- ---- Step 40: READY -- match-code description, guards ---------------
    -- Purpose: the original final SELECT, as a table.  The match-code
    -- description is looked up (lkp_mc), addresses already in
    -- STG_TRS_D_UNQ_ADDR are excluded (xu guard -- the insert-only
    -- replacement for IDQ's truncate), and one row per ADDR_ID is kept
    -- (first by derived line 1).  SRC_COUNTY is NULL (unfed port), as in
    -- the original.  Reads ONLY step 30.  This table is in target column
    -- order, so step 50 is a plain INSERT ... SELECT.
    CREATE OR REPLACE TRANSIENT TABLE WRK_TRS_ADDR1_S40_READY AS
    WITH
    lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common()))
    SELECT v.ADDR_ID, v.av:delivery_address_line1::VARCHAR AS ADDR_LN_1,
           v.av:delivery_address_line2::VARCHAR AS ADDR_LN_2,
           v.av:building_name::VARCHAR AS BLDNG_NM, v.av:sub_building_number::VARCHAR AS FLR_NUM,
           v.av:city::VARCHAR AS CITY, v.av:county_fips_cd::VARCHAR AS COUNTY,
           v.av:state_fips_cd::VARCHAR AS STATE, v.av:country_iso2_char::VARCHAR AS CNTRY_CD,
           v.av:zip_cd_5::VARCHAR AS PSTL_CD, v.av:zip_cd_4_extn::VARCHAR AS PSTL_CD_EXT,
           v.av:geocoding_latitude::NUMBER(38, 6) AS LATTD,
           v.av:geocoding_longitude::NUMBER(38, 6) AS LNGTD,
           v.av:match_code::VARCHAR AS VLDTN_MSG, mc.DESCRIPTION AS VLDTN_DESC,
           v.av:mailability_score::VARCHAR AS MLBLTY_SCR, v.av:address_type::VARCHAR AS ADDR_TP_CD,
           v.av:organization_descriptor::VARCHAR AS ORG_DESC,
           v.av:organization_name::VARCHAR AS ORG_NM, v.av:building_number::VARCHAR AS BLDG_NMBR,
           v.av:sub_building_complete::VARCHAR AS SUB_BLDG_NM,
           v.av:sub_building_descriptor::VARCHAR AS SUB_BLDG_DESC,
           v.av:geocoding_status::VARCHAR AS GEOCD_STS_CD,
           v.av:residential_delivery_indicator::VARCHAR AS RSDNTL_DLVRY_IND,
           v.av:status_info_result_percentage::VARCHAR AS ADDRDR_RSLT_PCT,
           v.av:early_warning_system_return_cd::VARCHAR AS ERLY_WRNG_CD,
           v.av:cass_error_code::VARCHAR AS CASS_ERR_CD,
           v.av:dpv_confirmation::VARCHAR AS DLVRY_PNT_VLDN,
           v.addr_line_1 AS SRC_ADDR_LN_1, v.addr_line_2 AS SRC_ADDR_LN_2,
           v.ADDR_CITY AS SRC_CITY, NULL AS SRC_COUNTY,
           v.ADDR_STATE_CD AS SRC_STATE, 'US' AS SRC_CNTRY,
           v.ADDR_ZIP5 AS SRC_PSTL_CD, v.ADDR_ZIP4 AS SRC_PSTL_CD_EXT,
           v.av:organization_department::VARCHAR AS ORG_DEPT
      FROM WRK_TRS_ADDR1_S30_VALIDATED v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = v.av:status_info_match_code::VARCHAR
      LEFT JOIN (SELECT DISTINCT ADDR_ID FROM STG_TRS_D_UNQ_ADDR) xu ON xu.ADDR_ID = v.ADDR_ID
     WHERE xu.ADDR_ID IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v.ADDR_ID ORDER BY v.addr_line_1) = 1;
    SELECT COUNT(*) INTO :l_rows FROM WRK_TRS_ADDR1_S40_READY;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'READY_TO_PUBLISH', 'COMPLETED', 'STG_TRS_D_UNQ_ADDR', :l_rows, NULL,
        'WRK_TRS_ADDR1_S40_READY', 'CREATED',
        'Publish-ready validated addresses: match-code description resolved, already-validated '
        || 'addresses excluded, one row per ADDR_ID (BR-31). Published in step 50.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 READY_TO_PUBLISH', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction.  If the INSERT fails, it rolls
    -- back, the checkpoints for steps 10-40 (already committed) survive,
    -- the work tables survive, and the run must be restarted from the beginning (step 5 cleanup, then step 10) 50.
    -- The INSERT below is the original INSERT, with the source changed
    -- from the validated CTE to step 40.  No TRUNCATE, no DELETE: the
    -- step-40 guard is what keeps this insert-only (see Parity notes).
    BEGIN TRANSACTION;
    INSERT INTO STG_TRS_D_UNQ_ADDR
           (ADDR_ID, ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD,
            LNGTD, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, BLDG_NMBR, SUB_BLDG_NM,
            SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ADDRDR_RSLT_PCT, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT,
            ORG_DEPT)
    SELECT ADDR_ID, ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD,
           LNGTD, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, BLDG_NMBR, SUB_BLDG_NM,
           SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ADDRDR_RSLT_PCT, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
           SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT,
           ORG_DEPT
      FROM WRK_TRS_ADDR1_S40_READY;
    l_rows := SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED', 'STG_TRS_D_UNQ_ADDR', :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: validated unique addresses to STG_TRS_D_UNQ_ADDR (BR-31). '
        || 'Count shown is rows inserted.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (STG_TRS_D_UNQ_ADDR)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_TRS_Addr_1 completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_TRS_Addr_1 failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
