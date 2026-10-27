-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty_Addr, workflow wf_FSS_Stage_Load.
--
-- What this mapping does, in plain words: it validates the FSS client
-- addresses (capture action not deleted, party not on the deactivation
-- list) and loads the good ones into the party-role address table.
-- Every active address is also written to the address-quality table,
-- and an address that fails validation is logged as an exception
-- instead of being loaded.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> active
--   -> validated -> flat -> scored -> final), one transaction, one
--   log line at the end.  If it failed, nothing told you which
--   logical stage had finished.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time.  No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE.  The final publish is the original INSERT ALL branches,
--   written as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--   No step before publish writes to a final target, so the target
--   read in a later step (keys already in the address table) still
--   sees the same target state as the original single statement did.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_FSS_ADDR_S1_SRC       source addresses, deactivated
--                                      parties removed, address key
--                                      built
--   Step 20  WRK_FSS_ADDR_S2_VALIDATED address validation result
--                                      attached, state code translated
--   Step 30  WRK_FSS_ADDR_S3_FLAT      validation result flattened
--                                      into plain columns, match-code
--                                      description resolved
--   Step 40  WRK_FSS_ADDR_S4_SCORED    good / exception score, held
--                                      address lines, exception
--                                      details, insert-only guards
--   Step 50  PUBLISH                   targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_FSS_ADDR_S1_SRC, WRK_FSS_ADDR_S2_VALIDATED,
--   WRK_FSS_ADDR_S3_FLAT, WRK_FSS_ADDR_S4_SCORED.  They live in the
--   same schema as the targets (unqualified names, as in the original
--   code), are prefixed WRK_FSS_, and are registered in the shared
--   job-control table at creation.  They survive a session crash
--   (TRANSIENT, not TEMP), which is what makes inspection after a run
--   possible.  A Snowflake CURSOR was NOT used: cursors process row by
--   row, and every step here is set-based by design -- the work table
--   IS the result set, held as a table instead of in memory, so it can
--   be counted and inspected after the run.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets.  The IDQ truncate of the address table is NOT
--     performed; keys already present are skipped instead (uq_addr
--     guard).  A re-run therefore inserts nothing twice, but it also
--     does not remove rows that IDQ would have truncated away.
--   * PRESERVED: the address type is the constant '002' (physical
--     mail), so the score depends only on the mailability score and
--     the match code; with the pass-through validator both are blank
--     and every address scores '100' (good).
--   * PRESERVED: the address-quality key adds the family marker 'F'
--     only for source type 'FSS_FAMILY', which never occurs in FSS
--     source rows (carried over from the mapping this one was copied
--     from).
--   * PRESERVED: the zip extension is blank on both the address and
--     the exception rows (the extension port is unfed), and the
--     period end date, period reference time and several address ports
--     are written as NULL (unfed ports), exactly as in the original.
--   * Version sequence is 1, the period start date is the create date,
--     the effective start date is the last-update date, and the
--     effective end date is NULL, exactly as in the original.
--
-- INSTALL
--   Install schema is FSS_ETL_WRK in database MDM_ETL_FSS.  All table
--   names in the code below are unqualified, as in the original code.
--   Shared control calls (sp_etl_job_begin / sp_etl_checkpoint /
--   sp_etl_job_finish / sp_etl_job_fail) take SOURCE first and live in
--   the shared framework; shared helpers are fn_snow_helperNN_common.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr (
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
    c_source     VARCHAR DEFAULT 'FSS';
    c_workflow   VARCHAR DEFAULT 'wf_FSS_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Addr';
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
    DROP TABLE IF EXISTS WRK_FSS_ADDR_S1_SRC;
    DROP TABLE IF EXISTS WRK_FSS_ADDR_S2_VALIDATED;
    DROP TABLE IF EXISTS WRK_FSS_ADDR_S3_FLAT;
    DROP TABLE IF EXISTS WRK_FSS_ADDR_S4_SCORED;

    -- ---- Step 10: SOURCE + REMOVE DEACTIVATED ------------------------------
    -- Purpose: the addresses to validate -- capture action not
    -- deleted, party not on the deactivation list -- with the address
    -- key built.  Every later step reads this table, never the raw
    -- source again.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_ADDR_S1_SRC AS
    SELECT s.*
      FROM (SELECT v.SOURCE_TYPE, v.ID_CLIENT, v.ADDR_LINE1, v.ADDR_LINE2, v.ADDR_CITY, v.CD_CNTY, v.ADDR_ZIP,
                   v.ADDR_STATE, v.PTY_SRC_KEY, v.ID_REGISTRATION_CLIENT, v.DT_LAST_UPDATE, v.DT_CREATED,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|002|' || NVL(LPAD(TO_VARCHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '')
                   || '|' || NVL(TRIM(UPPER(v.ADDR_LINE1)), '') || '|' || NVL(TRIM(UPPER(v.ADDR_LINE2)), '') || '|'
                   || NVL(UPPER(v.ADDR_CITY), '') || '|' || NVL(UPPER(v.ADDR_STATE), '') || '|' || NVL(v.ADDR_ZIP, '')
                                                                                                   AS pkey_src_object,
                   -- exp_Score_and_Exception_details.PTY_SRC_KEY (DQM_ADDRESS only)
                   LPAD(TO_VARCHAR(v.ID_CLIENT), 10, '0') || IFF(v.SOURCE_TYPE = 'FSS_FAMILY', 'F', '') AS dqm_pty_src_key
              FROM V_FSS_ETL_SRC v
             WHERE v.DTL__CAPXACTION <> 'D') s
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = s.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_ADDR_S1_SRC;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_ADDR_S1_SRC', 'CREATED',
        'Source addresses with the address key built, deactivated parties removed. '
        || 'Read by the validation step; never re-read the raw source after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: VALIDATE --------------------------------------------------
    -- Purpose: run the global address validation over each address and
    -- translate the state code.  Reads ONLY WRK_FSS_ADDR_S1_SRC (plus
    -- the state lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_ADDR_S2_VALIDATED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT a.*,
           fn_snow_helper34_common(a.ADDR_LINE1, a.ADDR_LINE2, a.ADDR_CITY, a.ADDR_STATE, a.ADDR_ZIP, 'US',
                                   st.MSTR_CODE_VALUE) AS av
      FROM WRK_FSS_ADDR_S1_SRC a
      LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'FSS'
                         AND st.SRC_CODE_VALUE = UPPER(TRIM(a.ADDR_STATE));
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_ADDR_S2_VALIDATED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'VALIDATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_ADDR_S2_VALIDATED', 'CREATED',
        'Addresses with the validation result attached and the state code translated. '
        || 'Read by the flattening step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 VALIDATED', :l_rows) || CHR(10);

    -- ---- Step 30: FLATTEN ----------------------------------------------------
    -- Purpose: flatten the validation result into plain columns
    -- (result address, postcode parts, county / state codes, latitude /
    -- longitude, organisation and building parts, match code and
    -- result percentage) and resolve the match-code description.
    -- Reads ONLY WRK_FSS_ADDR_S2_VALIDATED.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_ADDR_S3_FLAT AS
    WITH
    lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common()))
    SELECT v.*,
           v.av:delivery_address_line1::VARCHAR          AS a_line1,
           v.av:delivery_address_line2::VARCHAR          AS a_line2,
           v.av:city::VARCHAR                            AS a_city,
           v.av:postcode_complete::VARCHAR               AS a_postcode_complete,
           v.av:zip_cd_5::VARCHAR                        AS a_zip_cd_5,
           v.av:zip_cd_4_extn::VARCHAR                   AS a_zip_cd_4_extn,
           v.av:country_iso2_char::VARCHAR               AS a_country,
           v.av:mailability_score::VARCHAR               AS a_mailability_score,
           v.av:match_code::VARCHAR                      AS a_match_code,
           mc.DESCRIPTION                                AS a_match_code_description,
           fn_snow_helper04_common(v.av:status_info_result_percentage::VARCHAR, 2) AS a_result_pct,
           v.av:address_type::VARCHAR                    AS a_address_type,
           v.av:county_fips_cd::VARCHAR                  AS a_county_fips,
           v.av:state_fips_cd::VARCHAR                   AS a_state_fips,
           v.av:geocoding_latitude::NUMBER(38, 6)        AS a_latitude,
           v.av:geocoding_longitude::NUMBER(38, 6)       AS a_longitude,
           v.av:geocoding_status::VARCHAR                AS a_geocoding_status,
           v.av:residential_delivery_indicator::VARCHAR  AS a_residential,
           v.av:organization_name::VARCHAR               AS a_org_name,
           v.av:organization_descriptor::VARCHAR         AS a_org_descriptor,
           v.av:organization_department::VARCHAR         AS a_org_department,
           v.av:building_complete::VARCHAR               AS a_building_complete,
           v.av:building_name::VARCHAR                   AS a_building_name,
           v.av:building_number::VARCHAR                 AS a_building_number,
           v.av:sub_building_complete::VARCHAR           AS a_sub_building_complete,
           v.av:sub_building_descriptor::VARCHAR         AS a_sub_building_descriptor,
           v.av:early_warning_system_return_cd::VARCHAR  AS a_early_warning,
           v.av:cass_error_code::VARCHAR                 AS a_cass_error,
           v.av:dpv_confirmation::VARCHAR                AS a_dpv
      FROM WRK_FSS_ADDR_S2_VALIDATED v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = v.av:status_info_match_code::VARCHAR;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_ADDR_S3_FLAT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'FLAT', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_ADDR_S3_FLAT', 'CREATED',
        'Validation result flattened into plain columns with the match-code description resolved. '
        || 'Read by the scoring step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 FLAT', :l_rows) || CHR(10);

    -- ---- Step 40: SCORE -------------------------------------------------------
    -- Purpose: score every address (good / exception), build the held
    -- address lines, and set the exception details and the insert-only
    -- guards.  This is the only table step 50 reads.
    CREATE OR REPLACE TRANSIENT TABLE WRK_FSS_ADDR_S4_SCORED AS
    WITH
    scored AS (
        SELECT f.*,
               /* VALIDATION */ fn_snow_helper05_common('002', f.a_mailability_score, f.a_match_code) AS score,
               fn_snow_helper06_common('002', f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
               fn_snow_helper07_common(f.a_line1, f.a_line2)                          AS hold_line1,
               fn_snow_helper08_common(f.a_line1, f.a_line2)                          AS hold_line2
          FROM WRK_FSS_ADDR_S3_FLAT f
    )
    SELECT s.*,
           '002'                                                         AS addr_tp,
           'US'                                                          AS src_cntry,
           'FSS'                                                         AS src_sys,
           :l_run_ts                                                     AS run_ts,
           :c_mapping                                                    AS mapping_name,
           1 /* TIMELINE: VERSION_SEQ */                                 AS version_seq,
           1                                                             AS hub_state_ind,
           NVL(s.PTY_SRC_KEY, '') || '|Member'                           AS pty_rle_fk,
           'Primary'                                                     AS pref_lvl,
           NVL(TO_VARCHAR(s.ID_CLIENT), '') || '|' || NVL(TO_VARCHAR(s.ID_REGISTRATION_CLIENT), '') AS loc_idn,
           :P_MEMBER_HIERARCHY_CODE                                      AS hierarchy_code,
           :P_MEMBER_HM_REL_TP_CD                                        AS hm_rel_tp_cd,
           IFF(s.addr_issue_desc IS NOT NULL, 'Address', NULL)           AS exc_attribute_name,
           IFF(s.addr_issue_desc IS NOT NULL,
               NVL(s.ADDR_LINE1, '') || ' ' || NVL(s.ADDR_LINE2, '') || ' ' || NVL(s.ADDR_CITY, '') || ' '
               || NVL(s.ADDR_STATE, '') || ' ' || NVL(s.ADDR_ZIP, '') || '  US', NULL) AS exc_attribute_value,
           'Invalid_Address'                                             AS exc_code,
           'Invalid Address per Address Doctor'                          AS exc_desc,
           'Bad Value'                                                   AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY s.score, s.pkey_src_object
                                   ORDER BY s.DT_LAST_UPDATE DESC, s.ID_REGISTRATION_CLIENT) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                              AS uq_addr,
           ROW_NUMBER() OVER (PARTITION BY s.score, s.ID_CLIENT, s.ID_REGISTRATION_CLIENT, s.SOURCE_TYPE
                                  ORDER BY s.DT_LAST_UPDATE DESC) = 1    AS uq_addr_exc
      FROM scored s
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = s.pkey_src_object;
    SELECT COUNT(*) INTO :l_rows FROM WRK_FSS_ADDR_S4_SCORED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'SCORED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_FSS_ADDR_S4_SCORED', 'CREATED',
        'Scored addresses: good / exception score, held address lines, exception details and insert-only guards. '
        || 'This is the only table step 50 reads.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 SCORED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction.  If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must be restarted from the beginning.  The three INSERTs below are the three branches
    -- of the original INSERT ALL, in the same order, with the same
    -- column lists, values and WHERE conditions -- only the source
    -- changed, from the final CTE to step 40.
    l_rows := 0;
    BEGIN TRANSACTION;
    -- 50a. Every active address -> DQM_ADDRESS
    INSERT INTO DQM_ADDRESS
           (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
            RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
            LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
            ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
    SELECT a_mailability_score, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, ADDR_STATE, ADDR_ZIP, src_cntry, CD_CNTY,
           a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
           a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
           a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
           a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, addr_tp, src_sys,
           pkey_src_object, run_ts, dqm_pty_src_key, a_state_fips
      FROM WRK_FSS_ADDR_S4_SCORED;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50b. Good addresses -> C_S_FSS_PTY_RLE_ADDR
    INSERT INTO C_S_FSS_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, VERSION_SEQ,
            PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND,
            PTY_RLE_FK, ADDR_TP, USG_TP, PREF_LVL, HIERARCHY_CODE, HM_REL_TP_CD, LOC_IDN, SRC_LAST_UPD_DT,
            ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT,
            LCTN_CRDNT_DESC, LATTD, LNGTD, PSTL_BRCD, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC,
            ORG_NM, BLDG_NMBR, SUB_BLDG_NM, SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
            SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT,
            EFF_END_DT, PERIOD_START_DATE)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, version_seq, NULL, run_ts, mapping_name, DT_LAST_UPDATE,
           NULL, pkey_src_object, hub_state_ind, pty_rle_fk, addr_tp, NULL, pref_lvl, hierarchy_code,
           hm_rel_tp_cd, loc_idn, DT_LAST_UPDATE, hold_line1, hold_line2, a_building_name, NULL, a_city,
           a_county_fips, a_state_fips, a_country, a_zip_cd_5, a_zip_cd_4_extn, NULL, a_latitude,
           a_longitude, NULL, a_match_code, NULL, a_mailability_score, a_address_type, a_org_descriptor,
           a_org_name, a_building_number, a_sub_building_complete, a_sub_building_descriptor,
           a_geocoding_status, a_residential, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE,
           src_cntry, ADDR_ZIP, NULL, DT_LAST_UPDATE, NULL, DT_CREATED
      FROM WRK_FSS_ADDR_S4_SCORED
     WHERE score = '100' AND uq_addr;
    l_rows := l_rows + SQLROWCOUNT;
    -- 50c. Exception addresses -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
            EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
            ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
            SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
           exc_attribute_value, mapping_name, addr_tp, DT_LAST_UPDATE, NULL, exc_code, exc_desc, run_ts,
           exc_type, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE, ADDR_ZIP, NULL, src_cntry,
           ID_CLIENT, ID_REGISTRATION_CLIENT, SOURCE_TYPE
      FROM WRK_FSS_ADDR_S4_SCORED
     WHERE score = '40' AND uq_addr_exc;
    l_rows := l_rows + SQLROWCOUNT;
    COMMIT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'DQM_ADDRESS, C_S_FSS_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: every active address to the address-quality table, good addresses to the role address table, exception addresses to the exception table. '
        || 'Count shown is the total rows inserted by all three INSERTs.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_FSS_Pty_Addr completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_FSS_Pty_Addr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
