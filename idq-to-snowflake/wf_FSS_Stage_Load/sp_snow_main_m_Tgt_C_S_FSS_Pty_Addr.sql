--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Addr (workflow wf_FSS_Stage_Load; copied from the
-- ECI address mapping).
--
-- Validates the FSS client addresses (V_FSS_ETL_SRC, capture action not 'D') and loads the good ones into
-- C_S_FSS_PTY_RLE_ADDR (insert only, never truncated):
--   -> Fil_Inactive_recs: party (PTY_SRC_KEY) not in STG_FSS_PTY_INACTIVE_STS
--   -> mplt_Global_Addr_Validation (fn_snow_helper34_common), zip without extension
--   -> Write_DQM_ADDRESS (every active address)
--   -> rtr_Good_vs_Exception_Pty_Records: Good ('100') -> C_S_FSS_PTY_RLE_ADDR; Exception ('40') -> EXC row
--
-- VALIDATION: the address type is the constant '002' (physical mail), so the score (fn_snow_helper05_common)
--   depends only on the mailability score and the match code; with the pass-through validator both are NULL and
--   every address scores '100'.
-- BAD DATA: an exception address is not loaded, only logged ('Invalid Address per Address Doctor', 'Bad Value').
--   DQM_ADDRESS.PTY_SRC_KEY adds the family 'F' only for SOURCE_TYPE 'FSS_FAMILY', which never occurs (copied from
--   ECI, docs/common_insights.md section 10). Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, CREATOR, USG_TP,
--   LCTN_CRDNT_DESC, PSTL_BRCD, RGN_CD, SRC_PSTL_CD_EXT, ADDRESS_ZIP_EXT, PERIOD_END_DATE, FLR_NUM (router port
--   without input link). Unique keys Snowflake does not enforce are applied: C_S_FSS_PTY_RLE_ADDR (PKEY_SRC_OBJECT,
--   VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DT_CREATED, EFF_STRT_DT = DT_LAST_UPDATE; EFF_END_DT and
--   PERIOD_REFERENCE_TIME are linked to an unfed port (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr (
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',        -- $Member_Hierarchy_Code
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty_Addr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS
        WHEN TRUE THEN
            INTO DQM_ADDRESS
                 (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
                  LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
                  ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
                  MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
            VALUES (a_mailability_score, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, ADDR_STATE, ADDR_ZIP, src_cntry, CD_CNTY,
                    a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
                    a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
                    a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
                    a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, addr_tp, src_sys,
                    pkey_src_object, run_ts, dqm_pty_src_key, a_state_fips)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> exp_Address_Hold -> Write_C_S_FSS_PTY_RLE_ADDR
        WHEN score = '100' AND uq_addr THEN
            INTO C_S_FSS_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND,
                  PTY_RLE_FK, ADDR_TP, USG_TP, PREF_LVL, HIERARCHY_CODE, HM_REL_TP_CD, LOC_IDN, SRC_LAST_UPD_DT,
                  ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT,
                  LCTN_CRDNT_DESC, LATTD, LNGTD, PSTL_BRCD, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC,
                  ORG_NM, BLDG_NMBR, SUB_BLDG_NM, SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
                  SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT,
                  EFF_END_DT, PERIOD_START_DATE)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, version_seq, NULL, run_ts, mapping_name, DT_LAST_UPDATE,
                    NULL, pkey_src_object, hub_state_ind, pty_rle_fk, addr_tp, NULL, pref_lvl, hierarchy_code,
                    hm_rel_tp_cd, loc_idn, DT_LAST_UPDATE, hold_line1, hold_line2, a_building_name, NULL, a_city,
                    a_county_fips, a_state_fips, a_country, a_zip_cd_5, a_zip_cd_4_extn, NULL, a_latitude,
                    a_longitude, NULL, a_match_code, NULL, a_mailability_score, a_address_type, a_org_descriptor,
                    a_org_name, a_building_number, a_sub_building_complete, a_sub_building_descriptor,
                    a_geocoding_status, a_residential, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE,
                    src_cntry, ADDR_ZIP, NULL, DT_LAST_UPDATE, NULL, DT_CREATED)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_US_Addr_Exc_Rec -> write_Exc_Member_Rec
        WHEN score = '40' AND uq_addr_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
                  EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES (src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
                    exc_attribute_value, mapping_name, addr_tp, DT_LAST_UPDATE, NULL, exc_code, exc_desc, run_ts,
                    exc_type, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE, ADDR_ZIP, NULL, src_cntry,
                    ID_CLIENT, ID_REGISTRATION_CLIENT, SOURCE_TYPE)
    SELECT *
      FROM (
        WITH
        lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
        -- Read_V_FSS_ETL_SRC (source filter DTL__CAPXACTION <> 'D') + Exp_src + Exp_Build_Src_key
        src AS (
            SELECT v.SOURCE_TYPE, v.ID_CLIENT, v.ADDR_LINE1, v.ADDR_LINE2, v.ADDR_CITY, v.CD_CNTY, v.ADDR_ZIP,
                   v.ADDR_STATE, v.PTY_SRC_KEY, v.ID_REGISTRATION_CLIENT, v.DT_LAST_UPDATE, v.DT_CREATED,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|002|' || NVL(LPAD(TO_VARCHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '')
                   || '|' || NVL(TRIM(UPPER(v.ADDR_LINE1)), '') || '|' || NVL(TRIM(UPPER(v.ADDR_LINE2)), '') || '|'
                   || NVL(UPPER(v.ADDR_CITY), '') || '|' || NVL(UPPER(v.ADDR_STATE), '') || '|' || NVL(v.ADDR_ZIP, '')
                                                                                                   AS pkey_src_object,
                   -- exp_Score_and_Exception_details.PTY_SRC_KEY (DQM_ADDRESS only)
                   LPAD(TO_VARCHAR(v.ID_CLIENT), 10, '0') || IFF(v.SOURCE_TYPE = 'FSS_FAMILY', 'F', '') AS dqm_pty_src_key
              FROM V_FSS_ETL_SRC v
             WHERE v.DTL__CAPXACTION <> 'D'
        ),
        -- Lookup_STG_FSS_PTY_INACTIVE_STS + Fil_Inactive_recs
        active AS (
            SELECT s.*
              FROM src s
             WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = s.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        -- Exp_all_active (FULL_PSTL_CD: the extension port is unfed, so the zip alone) + mplt_Global_Addr_Validation
        validated AS (
            SELECT a.*,
                   fn_snow_helper34_common(a.ADDR_LINE1, a.ADDR_LINE2, a.ADDR_CITY, a.ADDR_STATE, a.ADDR_ZIP, 'US',
                                           st.MSTR_CODE_VALUE) AS av
              FROM active a
              LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'FSS'
                                 AND st.SRC_CODE_VALUE = UPPER(TRIM(a.ADDR_STATE))
        ),
        flat AS (
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
              FROM validated v
              LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = v.av:status_info_match_code::VARCHAR
        ),
        -- exp_Score_and_Exception_details + exp_Address_Hold
        scored AS (
            SELECT f.*,
                   /* VALIDATION */ fn_snow_helper05_common('002', f.a_mailability_score, f.a_match_code) AS score,
                   fn_snow_helper06_common('002', f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
                   fn_snow_helper07_common(f.a_line1, f.a_line2)                          AS hold_line1,
                   fn_snow_helper08_common(f.a_line1, f.a_line2)                          AS hold_line2
              FROM flat f
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
                 ON xa.PKEY_SRC_OBJECT = s.pkey_src_object
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (DQM_ADDRESS, C_S_FSS_PTY_RLE_ADDR, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
