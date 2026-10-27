-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr  --  MODULAR REWRITE
--
-- Original: IDQ mapping m_Tgt_C_S_WIC_Pty_Addr, workflow
-- wf_WIC_Stage_Load (copied from the ECI address mapping, per the
-- original header). Original Snowflake procedure
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.
--
-- What this mapping does, in plain words: it validates the WIC
-- addresses in V_WIC_ETL_SRC and loads the good ones into the
-- party-role address table. Every active address is first written to
-- the address-quality table DQM_ADDRESS. A good address (score '100')
-- loads into C_S_WIC_PTY_RLE_ADDR; an exception address (score '40')
-- is only logged as an exception, never loaded.
--
-- WHAT CHANGED FROM THE ORIGINAL SNOWFLAKE PROCEDURE
--   Original: one INSERT ALL statement, one CTE chain (active ->
--   validated -> flat -> scored -> final SELECT), one transaction, one
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
--   Step 10  WRK_WIC_ADDR_S10_ACTIVE     active source addresses only
--                                       (the deactivation-status
--                                       filter) + the address key
--   Step 20  WRK_WIC_ADDR_S20_VALIDATED  address validation (state
--                                       'TX', country 'US', zip only)
--   Step 30  WRK_WIC_ADDR_S30_FLAT       validation result pulled out
--                                       into flat columns + match-code
--                                       description
--   Step 40  WRK_WIC_ADDR_S40_SCORED     score, exception detail and
--                                       held address lines + run
--                                       constants + the insert-only
--                                       guards (uq_addr, uq_addr_exc)
--   Step 50  PUBLISH                     targets, in one transaction (see below)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WORK TABLES (all TRANSIENT)
--   WRK_WIC_ADDR_S10_ACTIVE, WRK_WIC_ADDR_S20_VALIDATED,
--   WRK_WIC_ADDR_S30_FLAT, WRK_WIC_ADDR_S40_SCORED. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code), are prefixed WRK_WIC_, and are registered in JOB_CONTROL_ETL
--   at creation. They survive a session crash (TRANSIENT, not TEMP),
--   which is what makes inspection after a run possible. A Snowflake
--   CURSOR was NOT used: cursors process row by row, and every step
--   here is set-based by design -- the work table IS the result set,
--   held as a table instead of in memory, so it can be counted and
--   inspected after the run.
--
-- INSTALL LOCATION
--   Install schema is WIC_ETL_WRK in database MDM_ETL_WIC. All table
--   names in the code below are unqualified, exactly as in the original.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ truncate of C_S_WIC_PTY_RLE_ADDR is
--     NOT performed; instead keys already present are skipped
--     (uq_addr guard).
--   * PRESERVED: address type is the constant '002', so the score
--     depends only on the mailability score and match code; with the
--     pass-through validator every address scores '100'.
--   * PRESERVED: an exception address is not loaded, only logged
--     ('Invalid Address per Address Doctor', 'Bad Value').
--   * PRESERVED: the unfed ports are written as NULL, exactly as in
--     the original -- ROWID_OBJECT, DELETED_*, CREATOR, USG_TP,
--     LCTN_CRDNT_DESC, PSTL_BRCD, RGN_CD, SRC_STATE (the source state
--     port is unfed even though 'TX' goes to the validator),
--     SRC_PSTL_CD_EXT, ADDRESS_STATE, ADDRESS_ZIP_EXT,
--     PERIOD_END_DATE, FLR_NUM.
--   * PRESERVED: DQM_ADDRESS.PTY_SRC_KEY is LPAD(ID, 10, '0'); the
--     ECI-only 'F' suffix never applies.
--   * PRESERVED: VERSION_SEQ = 1; PERIOD_START_DATE / EFF_STRT_DT =
--     DATE_ADDRESS_VALID_FROM; EFF_END_DT and PERIOD_REFERENCE_TIME
--     are NULL (linked to an unfed port).
--   * PRESERVED: the insert-only guard (uq_addr) is evaluated in step
--     40, before the publish transaction, against the target as it
--     stands at that point -- the same snapshot behaviour as the
--     original single INSERT ALL, whose source query was evaluated
--     once before any branch inserted.
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
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr (
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',        -- $Member_Hierarchy_Code
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr',   -- $Member_HM_REL_TP_CD
    P_JOB_RUN_ID            VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_source     VARCHAR DEFAULT 'WIC';
    c_workflow   VARCHAR DEFAULT 'wf_WIC_Stage_Load';
    c_mapping    VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Addr';
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
            'WIC_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS')
            || '_' || UUID_STRING());
    END IF;
    CALL sp_etl_job_begin(:c_source, :c_workflow, :c_mapping, :l_job_run_id);

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Work tables are NOT dropped at the end of a run, so any table this
    -- mapping created in a previous run is still in the database. Dropping
    -- them here, at the start of this run, is what makes a mapping-level
    -- restart work: the run then rebuilds every step from scratch.
    -- DROP TABLE IF EXISTS is a no-op if a table is already absent.
    DROP TABLE IF EXISTS WRK_WIC_ADDR_S10_ACTIVE;
    DROP TABLE IF EXISTS WRK_WIC_ADDR_S20_VALIDATED;
    DROP TABLE IF EXISTS WRK_WIC_ADDR_S30_FLAT;
    DROP TABLE IF EXISTS WRK_WIC_ADDR_S40_SCORED;

    -- ---- Step 10: ACTIVE -- deactivation filter + address key ------------
    -- Purpose: active source addresses only, each with its address key
    -- built from party key, member role, address type '002', file id and
    -- the upper-cased address parts. This is the only step that reads
    -- V_WIC_ETL_SRC; every later step reads work tables.
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_ADDR_S10_ACTIVE AS
    SELECT v.SOURCE_TABLE, v.ID, v.FID, v.DATE_ADDRESS_VALID_FROM, v.ADDRESS1, v.ADDRESS2, v.CITY, v.COUNTY,
           v.ZIP_CODE, v.PTY_SRC_KEY,
           NVL(v.PTY_SRC_KEY, '') || '|Member|002|' || NVL(LPAD(TO_VARCHAR(v.FID), 12, '0'), '') || '|'
           || NVL(TRIM(UPPER(v.ADDRESS1)), '') || '|' || NVL(TRIM(UPPER(v.ADDRESS2)), '') || '|'
           || NVL(UPPER(v.CITY), '') || '||' || NVL(v.ZIP_CODE, '')                      AS pkey_src_object
      FROM V_WIC_ETL_SRC v
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL);
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ADDR_S10_ACTIVE;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 10,
        'ACTIVE', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_ADDR_S10_ACTIVE', 'CREATED',
        'Active source addresses only, each with its address key built. '
        || 'Read by the validation step; the source view is not re-read after this point.',
        NULL, 'Step 10 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 10 ACTIVE', :l_rows) || CHR(10);

    -- ---- Step 20: VALIDATED -- address validation ------------------------
    -- Purpose: run every active address through the address validator
    -- with state 'TX', country 'US' and zip only, resolving the state
    -- code from the state lookup. Reads ONLY step 10 (plus the lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_ADDR_S20_VALIDATED AS
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT a.*,
           fn_snow_helper34_common(a.ADDRESS1, a.ADDRESS2, a.CITY, 'TX', a.ZIP_CODE, 'US', st.MSTR_CODE_VALUE) AS av
      FROM WRK_WIC_ADDR_S10_ACTIVE a
      LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'WIC' AND st.SRC_CODE_VALUE = 'TX';
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ADDR_S20_VALIDATED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 20,
        'VALIDATED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_ADDR_S20_VALIDATED', 'CREATED',
        'Every active address run through the address validator (state TX, country US, zip only). '
        || 'Read by the flattening step.',
        NULL, 'Step 20 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 20 VALIDATED', :l_rows) || CHR(10);

    -- ---- Step 30: FLAT -- validation result as flat columns --------------
    -- Purpose: pull the validation result object out into flat columns
    -- (result lines, city, postcode, country, scores, match code and
    -- its description, geocoding, organisation and building parts) so
    -- the scoring step works on plain columns. Reads ONLY step 20
    -- (plus the match-code lookup).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_ADDR_S30_FLAT AS
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
      FROM WRK_WIC_ADDR_S20_VALIDATED v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = v.av:status_info_match_code::VARCHAR;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ADDR_S30_FLAT;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 30,
        'FLAT', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_ADDR_S30_FLAT', 'CREATED',
        'Validation result pulled out into flat columns, with the match-code description resolved. '
        || 'Read by the scoring step.',
        NULL, 'Step 30 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 30 FLAT', :l_rows) || CHR(10);

    -- ---- Step 40: SCORED -- score, exception detail, held lines, guards --
    -- Purpose: the rows that publish will write. Each address is scored
    -- (good '100' or exception '40'), its exception detail and held
    -- address lines are derived, run constants are attached, and the
    -- insert-only guards are computed: first row per score + address
    -- key not already in the target (uq_addr), and first row per
    -- score + id + file id + source table for exceptions (uq_addr_exc).
    CREATE OR REPLACE TRANSIENT TABLE WRK_WIC_ADDR_S40_SCORED AS
    WITH
    scored AS (
        SELECT f.*,
               /* VALIDATION */ fn_snow_helper05_common('002', f.a_mailability_score, f.a_match_code) AS score,
               fn_snow_helper06_common('002', f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
               fn_snow_helper07_common(f.a_line1, f.a_line2)                          AS hold_line1,
               fn_snow_helper08_common(f.a_line1, f.a_line2)                          AS hold_line2
          FROM WRK_WIC_ADDR_S30_FLAT f
    )
    SELECT s.*,
           '002'                                                         AS addr_tp,
           'US'                                                          AS src_cntry,
           'WIC'                                                         AS src_sys,
           :l_run_ts                                                     AS run_ts,
           :c_mapping                                                    AS mapping_name,
           1 /* TIMELINE: VERSION_SEQ */                                 AS version_seq,
           1                                                             AS hub_state_ind,
           NVL(s.PTY_SRC_KEY, '') || '|Member'                           AS pty_rle_fk,
           LPAD(TO_VARCHAR(s.ID), 10, '0')                               AS dqm_pty_src_key,
           'Primary'                                                     AS pref_lvl,
           NVL(TO_VARCHAR(s.ID), '') || '|' || NVL(TO_VARCHAR(s.FID), '') AS loc_idn,
           :P_MEMBER_HIERARCHY_CODE                                      AS hierarchy_code,
           :P_MEMBER_HM_REL_TP_CD                                        AS hm_rel_tp_cd,
           IFF(s.addr_issue_desc IS NOT NULL, 'Address', NULL)           AS exc_attribute_name,
           IFF(s.addr_issue_desc IS NOT NULL,
               NVL(s.ADDRESS1, '') || ' ' || NVL(s.ADDRESS2, '') || ' ' || NVL(s.CITY, '') || '  '
               || NVL(s.ZIP_CODE, '') || '  US', NULL)                   AS exc_attribute_value,
           'Invalid_Address'                                             AS exc_code,
           'Invalid Address per Address Doctor'                          AS exc_desc,
           'Bad Value'                                                   AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY s.score, s.pkey_src_object
                                   ORDER BY s.DATE_ADDRESS_VALID_FROM DESC, s.FID) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                              AS uq_addr,
           ROW_NUMBER() OVER (PARTITION BY s.score, s.ID, s.FID, s.SOURCE_TABLE
                                  ORDER BY s.DATE_ADDRESS_VALID_FROM DESC) = 1 AS uq_addr_exc
      FROM scored s
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = s.pkey_src_object;
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ADDR_S40_SCORED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 40,
        'SCORED', 'COMPLETED', NULL, :l_rows, NULL,
        'WRK_WIC_ADDR_S40_SCORED', 'CREATED',
        'Scored rows: good / exception score, exception detail, held address lines, run constants, and '
        || 'insert-only guards (uq_addr, uq_addr_exc). Read by the publish step; the target guard is '
        || 'evaluated here, before publish, as in the original single query.',
        NULL, 'Step 40 complete.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 40 SCORED', :l_rows) || CHR(10);

    -- ---- Step 50: PUBLISH -- one transaction, all targets ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. If any INSERT fails, the
    -- whole publish rolls back, the checkpoints for steps 10-40 (already
    -- committed) survive, the work tables survive, and the mapping must
    -- be restarted from the beginning. The three INSERTs below are the
    -- three branches of the original INSERT ALL, in the same order, with
    -- the same column lists, values and WHEN conditions -- only the
    -- source changed, from the original query to step 40.
    BEGIN TRANSACTION;
    -- 50a. Every active address -> DQM_ADDRESS
    INSERT INTO DQM_ADDRESS
           (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
            RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
            LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
            ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
    SELECT a_mailability_score, ADDRESS1, ADDRESS2, CITY, NULL, ZIP_CODE, src_cntry, COUNTY,
           a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
           a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
           a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
           a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, addr_tp, src_sys,
           pkey_src_object, run_ts, dqm_pty_src_key, a_state_fips
      FROM WRK_WIC_ADDR_S40_SCORED;
    -- 50b. Good addresses -> C_S_WIC_PTY_RLE_ADDR
    INSERT INTO C_S_WIC_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            VERSION_SEQ, UPDATED_BY, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN, HM_REL_TP_CD, HUB_STATE_IND,
            SRC_ROWID, USG_TP, HIERARCHY_CODE, ADDR_LN_1, ADDR_LN_2, SRC_LAST_UPD_DT, FLR_NUM, LCTN_CRDNT_DESC,
            PSTL_BRCD, RGN_CD, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY,
            SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT, ADDR_TP, PTY_RLE_FK, CREATE_DATE, CREATOR,
            PERIOD_REFERENCE_TIME, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, COUNTY, MLBLTY_SCR, STATE,
            RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM,
            SUB_BLDG_DESC, BLDG_NMBR, PSTL_CD_EXT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, DATE_ADDRESS_VALID_FROM, version_seq, mapping_name,
           run_ts, pref_lvl, loc_idn, hm_rel_tp_cd, hub_state_ind, pkey_src_object, NULL, hierarchy_code,
           hold_line1, hold_line2, DATE_ADDRESS_VALID_FROM, NULL, NULL, NULL, NULL, ADDRESS1, ADDRESS2, CITY,
           COUNTY, NULL, src_cntry, ZIP_CODE, NULL, DATE_ADDRESS_VALID_FROM, NULL, addr_tp, pty_rle_fk,
           DATE_ADDRESS_VALID_FROM, NULL, NULL, a_city, a_zip_cd_5, a_country, a_match_code, a_latitude,
           a_longitude, a_county_fips, a_mailability_score, a_state_fips, a_residential, a_org_descriptor,
           a_address_type, a_org_name, a_building_name, a_geocoding_status, a_sub_building_complete,
           a_sub_building_descriptor, a_building_number, a_zip_cd_4_extn
      FROM WRK_WIC_ADDR_S40_SCORED
     WHERE score = '100' AND uq_addr;
    -- 50c. Exception addresses -> EXC_STG_BAD_REC_MEMB
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
            EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
            ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
            SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
           exc_attribute_value, mapping_name, addr_tp, DATE_ADDRESS_VALID_FROM, NULL, exc_code, exc_desc,
           run_ts, exc_type, ADDRESS1, ADDRESS2, CITY, COUNTY, NULL, ZIP_CODE, NULL, src_cntry, ID, FID,
           SOURCE_TABLE
      FROM WRK_WIC_ADDR_S40_SCORED
     WHERE score = '40' AND uq_addr_exc;
    COMMIT;
    -- Publish row counts by branch are not summed here; report the
    -- scored-row count that fed the publish instead.
    SELECT COUNT(*) INTO :l_rows FROM WRK_WIC_ADDR_S40_SCORED;
    CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'WORKING', 50,
        'PUBLISH', 'COMPLETED',
        'DQM_ADDRESS, C_S_WIC_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB',
        :l_rows, NULL, NULL, 'NONE', NULL, NULL,
        'Published in one transaction: every active address to DQM_ADDRESS, good addresses to '
        || 'C_S_WIC_PTY_RLE_ADDR, and exception addresses to EXC_STG_BAD_REC_MEMB. Count shown is scored '
        || 'rows feeding the publish; each branch inserts only its own WHEN-filtered subset.');
    l_summary := l_summary || fn_snow_helper36_common(:c_mapping, 'step 50 PUBLISH (scored rows)', :l_rows) || CHR(10);

    -- ---- TERMINATING ------------------------------------------------------
    CALL sp_etl_job_finish(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
        'm_Tgt_C_S_WIC_Pty_Addr completed. JOB_RUN_ID = ' || :l_job_run_id);
    RETURN 'JOB_RUN_ID=' || :l_job_run_id || CHR(10) || l_summary;
EXCEPTION
    WHEN OTHER THEN
        -- Roll back the publish transaction if one is open (harmless if
        -- none is), then write the FAILED terminating row -- AFTER the
        -- rollback, so it is NOT rolled back. Work tables are NOT
        -- dropped here: that is the whole point of KEPT. The caller
        -- (workflow runner) will see the raise and stop the workflow;
        -- the operator restarts the mapping with a new run.
        ROLLBACK;
        CALL sp_etl_checkpoint(:c_source, :l_job_run_id, :c_workflow, :c_mapping, 'TERMINATING', 999,
            'JOB_END', 'FAILED', NULL, NULL, NULL, NULL, 'KEPT', NULL, NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See VW_ETL_OPEN_WORK_TABLES for this JOB_RUN_ID and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        CALL sp_etl_job_fail(:c_source, :l_job_run_id, :c_workflow, :c_mapping,
            'm_Tgt_C_S_WIC_Pty_Addr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END;
$$;
