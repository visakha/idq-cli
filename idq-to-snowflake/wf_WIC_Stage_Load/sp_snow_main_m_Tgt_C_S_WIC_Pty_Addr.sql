--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Addr (workflow wf_WIC_Stage_Load; copied from the
-- ECI address mapping).
--
-- Validates the WIC addresses (V_WIC_ETL_SRC) and loads the good ones into C_S_WIC_PTY_RLE_ADDR (insert only, never
-- truncated):
--   -> Fil_Inactive_recs: party (PTY_SRC_KEY) not in STG_WIC_PTY_INACTIVE_STS
--   -> mplt_Global_Addr_Validation (fn_snow_helper34_common) with state 'TX', country 'US', zip only
--   -> Write_DQM_ADDRESS (every active address)
--   -> rtr_Good_vs_Exception_Pty_Records: Good ('100') -> C_S_WIC_PTY_RLE_ADDR; Exception ('40') -> EXC row
--
-- VALIDATION: constant address type '002', so the score (fn_snow_helper05_common) depends only on the mailability
--   score and match code; with the pass-through validator every address scores '100'.
-- BAD DATA: an exception address is not loaded, only logged ('Invalid Address per Address Doctor', 'Bad Value').
--   Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, CREATOR, USG_TP, LCTN_CRDNT_DESC, PSTL_BRCD, RGN_CD,
--   SRC_STATE (the source state port is unfed even though 'TX' goes to the validator), SRC_PSTL_CD_EXT,
--   ADDRESS_STATE, ADDRESS_ZIP_EXT, PERIOD_END_DATE, FLR_NUM (router port without input link). DQM_ADDRESS.PTY_SRC_KEY
--   is LPAD(ID, 10, '0'); the ECI-only 'F' suffix never applies. Unique keys Snowflake does not enforce are applied:
--   C_S_WIC_PTY_RLE_ADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE / EFF_STRT_DT = DATE_ADDRESS_VALID_FROM; EFF_END_DT and
--   PERIOD_REFERENCE_TIME are linked to an unfed port (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr (
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',        -- $Member_Hierarchy_Code
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty_Addr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_WIC_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS
        WHEN TRUE THEN
            INTO DQM_ADDRESS
                 (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
                  LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
                  ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
                  MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
            VALUES (a_mailability_score, ADDRESS1, ADDRESS2, CITY, NULL, ZIP_CODE, src_cntry, COUNTY,
                    a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
                    a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
                    a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
                    a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, addr_tp, src_sys,
                    pkey_src_object, run_ts, dqm_pty_src_key, a_state_fips)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> exp_Address_Hold -> Write_C_S_WIC_PTY_RLE_ADDR
        WHEN score = '100' AND uq_addr THEN
            INTO C_S_WIC_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  VERSION_SEQ, UPDATED_BY, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN, HM_REL_TP_CD, HUB_STATE_IND,
                  SRC_ROWID, USG_TP, HIERARCHY_CODE, ADDR_LN_1, ADDR_LN_2, SRC_LAST_UPD_DT, FLR_NUM, LCTN_CRDNT_DESC,
                  PSTL_BRCD, RGN_CD, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY,
                  SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT, ADDR_TP, PTY_RLE_FK, CREATE_DATE, CREATOR,
                  PERIOD_REFERENCE_TIME, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, COUNTY, MLBLTY_SCR, STATE,
                  RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM,
                  SUB_BLDG_DESC, BLDG_NMBR, PSTL_CD_EXT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, DATE_ADDRESS_VALID_FROM, version_seq, mapping_name,
                    run_ts, pref_lvl, loc_idn, hm_rel_tp_cd, hub_state_ind, pkey_src_object, NULL, hierarchy_code,
                    hold_line1, hold_line2, DATE_ADDRESS_VALID_FROM, NULL, NULL, NULL, NULL, ADDRESS1, ADDRESS2, CITY,
                    COUNTY, NULL, src_cntry, ZIP_CODE, NULL, DATE_ADDRESS_VALID_FROM, NULL, addr_tp, pty_rle_fk,
                    DATE_ADDRESS_VALID_FROM, NULL, NULL, a_city, a_zip_cd_5, a_country, a_match_code, a_latitude,
                    a_longitude, a_county_fips, a_mailability_score, a_state_fips, a_residential, a_org_descriptor,
                    a_address_type, a_org_name, a_building_name, a_geocoding_status, a_sub_building_complete,
                    a_sub_building_descriptor, a_building_number, a_zip_cd_4_extn)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_US_Addr_Exc_Rec -> write_Exc_Member_Rec
        WHEN score = '40' AND uq_addr_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
                  EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES (src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
                    exc_attribute_value, mapping_name, addr_tp, DATE_ADDRESS_VALID_FROM, NULL, exc_code, exc_desc,
                    run_ts, exc_type, ADDRESS1, ADDRESS2, CITY, COUNTY, NULL, ZIP_CODE, NULL, src_cntry, ID, FID,
                    SOURCE_TABLE)
    SELECT *
      FROM (
        WITH
        lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
        -- Read_V_WIC_ETL_SRC + Exp_src + Exp_Build_Src_key + Lookup_STG_WIC_PTY_INACTIVE_STS + Fil_Inactive_recs
        active AS (
            SELECT v.SOURCE_TABLE, v.ID, v.FID, v.DATE_ADDRESS_VALID_FROM, v.ADDRESS1, v.ADDRESS2, v.CITY, v.COUNTY,
                   v.ZIP_CODE, v.PTY_SRC_KEY,
                   NVL(v.PTY_SRC_KEY, '') || '|Member|002|' || NVL(LPAD(TO_VARCHAR(v.FID), 12, '0'), '') || '|'
                   || NVL(TRIM(UPPER(v.ADDRESS1)), '') || '|' || NVL(TRIM(UPPER(v.ADDRESS2)), '') || '|'
                   || NVL(UPPER(v.CITY), '') || '||' || NVL(v.ZIP_CODE, '')                      AS pkey_src_object
              FROM V_WIC_ETL_SRC v
             WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        -- Exp_all_active + mplt_Global_Addr_Validation (state 'TX' passed in; lkp_State_Cd on 'TX')
        validated AS (
            SELECT a.*,
                   fn_snow_helper34_common(a.ADDRESS1, a.ADDRESS2, a.CITY, 'TX', a.ZIP_CODE, 'US', st.MSTR_CODE_VALUE) AS av
              FROM active a
              LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'WIC' AND st.SRC_CODE_VALUE = 'TX'
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
                 ON xa.PKEY_SRC_OBJECT = s.pkey_src_object
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (DQM_ADDRESS, C_S_WIC_PTY_RLE_ADDR, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
