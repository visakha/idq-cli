-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr  --  MODULAR REWRITE
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Validates the ECI child and family addresses and loads the good
--   ones into the party-role address table. Every active address is
--   also written to the address-quality table, and bad addresses are
--   logged as exceptions instead of loading.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (src -> keyed
--   -> validated -> flat -> scored -> final SELECT), one transaction,
--   one log line at the end.
--   This rewrite: the SAME business SQL, split at the CTE boundaries
--   into named work tables, one step at a time. No business expression
--   was changed; each step's SELECT is the original CTE, with its FROM
--   clause pointed at the previous work table instead of the previous
--   CTE. The final publish is the original INSERT ALL branches, written
--   as separate INSERT statements (one per target) inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_ADR_S10_SRC      address source rows with party /
--                                     role keys and the translated
--                                     address type
--   Step 20  WRK_ECI_ADR_S20_KEYED    record keys + active addresses
--                                     only (no deactivation status)
--   Step 30  WRK_ECI_ADR_S30_VALIDATED address validation result
--                                     (pass-through stand-in) + state
--                                     lookup
--   Step 40  WRK_ECI_ADR_S40_FLAT     validation result unpacked +
--                                     match-code description
--   Step 50  WRK_ECI_ADR_S50_READY    score, issue description, held
--                                     address lines and insert-only
--                                     guards
--   Step 60  PUBLISH                targets, in one transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_ADR_S10_SRC, WRK_ECI_ADR_S20_KEYED,
--   WRK_ECI_ADR_S30_VALIDATED, WRK_ECI_ADR_S40_FLAT,
--   WRK_ECI_ADR_S50_READY. They live in the same schema as the targets
--   (unqualified names, as in the original code) and are prefixed
--   WRK_ECI_. They survive a session crash (TRANSIENT, not TEMP). No
--   CURSOR was used: every step here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. IDQ truncates C_S_ECI_PTY_RLE_ADDR; the
--     Snowflake version instead skips keys already present (uq_addr
--     guard).
--   * Score '40' means: address type not physical mail (002) and
--     mailability <= '3'; physical mail with mailability < '3' and a
--     match code starting I / N; or an address type that does not
--     translate. Comparisons are on strings, as in IDQ; preserved via
--     fn_snow_helper05_common.
--   * The address validator is the pass-through stand-in for
--     AddressDoctor: mailability and match code are NULL, so every
--     address with a known type scores '100'; preserved via
--     fn_snow_helper34_common.
--   * An exception address is not loaded, only logged, with the
--     hard-coded description 'Invalid Address per Address Doctor' and
--     type 'Bad Value' (no exception-catalogue lookup in this mapping);
--     preserved. Scores are always '40' or '100', so no row reaches
--     the router default group; preserved.
--   * Ports linked to targets but fed by nothing in IDQ are written as
--     NULL (ROWID_OBJECT, DELETED_*, CREATOR, PSTL_BRCD, RGN_CD,
--     LCTN_CRDNT_DESC, EFF_END_DT, the exception PERIOD_END_DATE, and
--     FLR_NUM: the router port Sub_buildingNumber has no input link);
--     preserved.
--   * VERSION_SEQ is 1. PERIOD_REFERENCE_TIME is the run start when
--     EFF_END_DT is set; EFF_END_DT is not linked in IDQ, so it is
--     NULL and PERIOD_REFERENCE_TIME is NULL; preserved.
--   * PERIOD_START_DATE / EFF_STRT_DT is source LAST_UPDATE_DATE;
--     preserved.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so
--   every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr (
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
    c_source     VARCHAR DEFAULT 'ECI';
    c_workflow   VARCHAR DEFAULT 'wf_ECI_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Addr';
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
    DROP TABLE IF EXISTS WRK_ECI_ADR_S10_SRC;
    DROP TABLE IF EXISTS WRK_ECI_ADR_S20_KEYED;
    DROP TABLE IF EXISTS WRK_ECI_ADR_S30_VALIDATED;
    DROP TABLE IF EXISTS WRK_ECI_ADR_S40_FLAT;
    DROP TABLE IF EXISTS WRK_ECI_ADR_S50_READY;

    -- ---- Step 10: ADDRESS SOURCE ROWS ------------------------------------
    -- Purpose: the address source rows with the party key, role key
    -- and translated address type. This is the original src CTE
    -- (source view + address-type lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ADR_S10_SRC AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT s.SOURCE_TABLE, s.ID, s.ID_FAMILY_ADDRESS, s.ADDRESS1, s.ADDRESS2, s.ADDRESS_CD, s.CITY_NAME,
           s.COUNTY_NAME, s.STATE_ABBREV, s.ZIP_CODE, s.ZIP_SFX, s.LAST_UPDATE_DATE,
           LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')   AS pty_src_key,
           LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member'
                                                                                           AS pty_rle_fk,
           at.MSTR_CODE_VALUE                                                              AS mstr_addr_tp
      FROM V_ECI_ETL_SRC_FAMILY_ADDRESS s
      LEFT JOIN lkp_cv at ON at.CODE_TYPE = 'ADDR_TP' AND at.SRC_SYS = 'ECI'
                         AND at.SRC_CODE_VALUE = s.ADDRESS_CD;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ADR_S10_SRC;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'SRC_ADDRESSES', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ADR_S10_SRC', 'CREATED',
        'Address source rows with party / role keys and translated address types. '
        || 'Read by the keying step; the source view is not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 SRC_ADDRESSES', :l_rows) || CHR(10);

    -- ---- Step 20: RECORD KEYS + ACTIVE ONLY -------------------------------
    -- Purpose: build the record key and drop addresses whose party has
    -- a deactivation status. This is the original keyed CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ADR_S20_KEYED AS
    SELECT s.*,
           s.pty_rle_fk || '|' || NVL(s.mstr_addr_tp, '') || '|'
           || NVL(LPAD(TO_VARCHAR(s.ID_FAMILY_ADDRESS), 10, '0'), '') || '|'
           || NVL(TRIM(UPPER(s.ADDRESS1)), '') || '|' || NVL(TRIM(UPPER(s.ADDRESS2)), '') || '|'
           || NVL(UPPER(s.CITY_NAME), '') || '|' || NVL(UPPER(s.STATE_ABBREV), '') || '|'
           || NVL(s.ZIP_CODE, '') || '|' || NVL(s.ZIP_SFX, '')                             AS pkey_src_object
      FROM WRK_ECI_ADR_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = s.pty_src_key AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ADR_S20_KEYED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'KEYED_ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ADR_S20_KEYED', 'CREATED',
        'Active addresses only, each with its record key. Read by the validation step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 KEYED_ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 30: ADDRESS VALIDATION --------------------------------------
    -- Purpose: run the address validator (pass-through stand-in for
    -- AddressDoctor) with the state-code lookup. Reads ONLY step 20.
    -- This is the original validated CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ADR_S30_VALIDATED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT k.*,
           fn_snow_helper34_common(k.ADDRESS1, k.ADDRESS2, k.CITY_NAME, k.STATE_ABBREV,
                                   NVL(k.ZIP_CODE, '') || IFF(k.ZIP_SFX IS NOT NULL, '-' || k.ZIP_SFX, ''),
                                   'US', st.MSTR_CODE_VALUE) AS av
      FROM WRK_ECI_ADR_S20_KEYED k
      LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'ECI'
                         AND st.SRC_CODE_VALUE = UPPER(TRIM(k.STATE_ABBREV));
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ADR_S30_VALIDATED;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'ADDR_VALIDATION', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ADR_S30_VALIDATED', 'CREATED',
        'Validated addresses (pass-through stand-in for AddressDoctor). '
        || 'Read by the unpacking step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 ADDR_VALIDATION', :l_rows) || CHR(10);

    -- ---- Step 40: UNPACK VALIDATION RESULT ---------------------------------
    -- Purpose: unpack the structured validation result into flat
    -- columns and resolve the match-code description. Reads ONLY step
    -- 30. This is the original flat CTE.
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ADR_S40_FLAT AS
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
      FROM WRK_ECI_ADR_S30_VALIDATED v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = v.av:status_info_match_code::VARCHAR;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ADR_S40_FLAT;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'FLAT_VALIDATION', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_ECI_ADR_S40_FLAT', 'CREATED',
        'Unpacked validation results with match-code descriptions. Read by the scoring step.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 FLAT_VALIDATION', :l_rows) || CHR(10);

    -- ---- Step 50: SCORE + READY ----------------------------------------------
    -- Purpose: score each address ('100' good, '40' exception), build
    -- the exception detail and the held (scrubbed) address lines, and
    -- apply the insert-only guards. Reads ONLY step 40. This is the
    -- original scored CTE plus the final SELECT (including the
    -- target-table guard join, which still sees the pre-run state
    -- because nothing has been published yet).
    CREATE OR REPLACE TRANSIENT TABLE WRK_ECI_ADR_S50_READY AS
    WITH
    scored AS (
        SELECT f.*,
               fn_snow_helper05_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code) AS score,
               fn_snow_helper06_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
               fn_snow_helper07_common(f.a_line1, f.a_line2)                                   AS hold_line1,
               fn_snow_helper08_common(f.a_line1, f.a_line2)                                   AS hold_line2
          FROM WRK_ECI_ADR_S40_FLAT f
    )
    SELECT s.*,
           'US'                                                          AS src_cntry,
           'ECI'                                                         AS src_sys,
           :l_run_ts                                                     AS run_ts,
           :c_mapping                                                    AS mapping_name,
           1 /* TIMELINE: VERSION_SEQ */                                 AS version_seq,
           1                                                             AS hub_state_ind,
           'Primary'                                                     AS pref_lvl,
           TO_VARCHAR(TRUNC(s.ID)) || '|' || TO_VARCHAR(TRUNC(s.ID_FAMILY_ADDRESS)) AS loc_idn,
           :P_MEMBER_HIERARCHY_CODE                                      AS hierarchy_code,
           :P_MEMBER_HM_REL_TP_CD                                        AS hm_rel_tp_cd,
           IFF(s.addr_issue_desc IS NOT NULL, 'Address', NULL)           AS exc_attribute_name,
           IFF(s.addr_issue_desc IS NOT NULL,
               NVL(s.ADDRESS1, '') || ' ' || NVL(s.ADDRESS2, '') || ' ' || NVL(s.CITY_NAME, '') || ' '
               || NVL(s.STATE_ABBREV, '') || ' ' || NVL(s.ZIP_CODE, '') || ' ' || NVL(s.ZIP_SFX, '') || ' US',
               NULL)                                                     AS exc_attribute_value,
           'Invalid_Address'                                             AS exc_code,
           'Invalid Address per Address Doctor'                          AS exc_desc,
           'Bad Value'                                                   AS exc_type,
           (ROW_NUMBER() OVER (PARTITION BY s.score, s.pkey_src_object
                                   ORDER BY s.LAST_UPDATE_DATE DESC, s.ID_FAMILY_ADDRESS) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                              AS uq_addr,
           ROW_NUMBER() OVER (PARTITION BY s.score, s.ID, s.ID_FAMILY_ADDRESS, s.SOURCE_TABLE
                                  ORDER BY s.LAST_UPDATE_DATE DESC) = 1  AS uq_addr_exc
      FROM scored s
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = s.pkey_src_object;
    SELECT COUNT(*) INTO :l_rows FROM WRK_ECI_ADR_S50_READY;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'SCORED_READY', 'COMPLETED', 'DQM_ADDRESS, C_S_ECI_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB', :l_rows, NULL,
        'WRK_ECI_ADR_S50_READY', 'CREATED',
        'Scored, publish-ready addresses with held lines and insert-only guards (uq_addr, '
        || 'uq_addr_exc). Published in step 60.',
        NULL, 'Step 50 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 SCORED_READY', :l_rows) || CHR(10);

    -- ---- Step 60: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The three INSERTs below are
    -- the three branches of the original INSERT ALL, in the same order
    -- (address-quality table first, then good addresses, then
    -- exceptions), with the same column lists, values and WHERE
    -- conditions -- only the source changed, from the final SELECT to
    -- step 50. No TRUNCATE, no DELETE.
    BEGIN TRANSACTION;
    -- 60a. Every active address -> DQM_ADDRESS
    INSERT INTO DQM_ADDRESS
           (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
            RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
            LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
            ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
    SELECT a_mailability_score, ADDRESS1, ADDRESS2, CITY_NAME, STATE_ABBREV, ZIP_CODE, src_cntry, COUNTY_NAME,
           a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
           a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
           a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
           a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, mstr_addr_tp, src_sys,
           pkey_src_object, run_ts, pty_src_key, a_state_fips
      FROM WRK_ECI_ADR_S50_READY;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60b. Good addresses (score 100) -> C_S_ECI_PTY_RLE_ADDR
    INSERT INTO C_S_ECI_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            VERSION_SEQ, UPDATED_BY, CREATE_DATE, CREATOR, ADDR_TP, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN,
            SRC_ROWID, HUB_STATE_IND, HIERARCHY_CODE, HM_REL_TP_CD, PERIOD_REFERENCE_TIME, ADDR_LN_1,
            ADDR_LN_2, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, PSTL_BRCD, RGN_CD, COUNTY,
            LCTN_CRDNT_DESC, MLBLTY_SCR, STATE, RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, FLR_NUM,
            BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM, SUB_BLDG_DESC, BLDG_NMBR, SRC_ADDR_LN_1, SRC_ADDR_LN_2,
            SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT,
            PTY_RLE_FK, SRC_LAST_UPD_DT, PSTL_CD_EXT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, LAST_UPDATE_DATE, version_seq, mapping_name,
           LAST_UPDATE_DATE, NULL, mstr_addr_tp, run_ts, pref_lvl, loc_idn, pkey_src_object, hub_state_ind,
           hierarchy_code, hm_rel_tp_cd, NULL, hold_line1, hold_line2, a_city, a_zip_cd_5, a_country,
           a_match_code, a_latitude, a_longitude, NULL, NULL, a_county_fips, NULL, a_mailability_score,
           a_state_fips, a_residential, a_org_descriptor, a_address_type, a_org_name, NULL,
           a_building_name, a_geocoding_status, a_sub_building_complete, a_sub_building_descriptor,
           a_building_number, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, src_cntry, ZIP_CODE,
           ZIP_SFX, LAST_UPDATE_DATE, NULL, pty_rle_fk, LAST_UPDATE_DATE, a_zip_cd_4_extn
      FROM WRK_ECI_ADR_S50_READY
     WHERE score = '100' AND uq_addr;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    -- 60c. Exception addresses (score 40) -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
            EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
            ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
            SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
           exc_attribute_value, mapping_name, ADDRESS_CD, LAST_UPDATE_DATE, NULL, exc_code, exc_desc,
           run_ts, exc_type, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, ZIP_CODE, ZIP_SFX,
           src_cntry, ID, ID_FAMILY_ADDRESS, SOURCE_TABLE
      FROM WRK_ECI_ADR_S50_READY
     WHERE score = '40' AND uq_addr_exc;
    l_pub_rows := l_pub_rows + SQLROWCOUNT;
    COMMIT;
    l_rows := l_pub_rows;
    CALL sp_etl_checkpoint('ECI', :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 60,
        'PUBLISH', 'COMPLETED',
        'DQM_ADDRESS, C_S_ECI_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: address-quality rows, good addresses and exception rows. '
        || 'Count shown is rows inserted across all publish branches.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 60 PUBLISH', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish('ECI', :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_ECI_Pty_Addr completed. JOB_RUN_ID = ' || :l_job_run_id);
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
            'm_Tgt_C_S_ECI_Pty_Addr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
