--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_WIC_Pty_Addr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Addr (workflow wf_WIC_Stage_Load; copied from the ECI address
-- mapping).
--
-- Validates the WIC addresses (V_WIC_ETL_SRC) and loads the good ones into C_S_WIC_PTY_RLE_ADDR (truncated first):
--   -> Fil_Inactive_recs: party (PTY_SRC_KEY) not in STG_WIC_PTY_INACTIVE_STS
--   -> mplt_Global_Addr_Validation (fn_dq_valid_global_addr) with state 'TX', country 'US', zip only
--   -> Write_DQM_ADDRESS (every active address)
--   -> rtr_Good_vs_Exception_Pty_Records: Good ('100') -> C_S_WIC_PTY_RLE_ADDR; Exception ('40') -> EXC row
-- The address type is the constant '002'.
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE / EFF_STRT_DT = DATE_ADDRESS_VALID_FROM; EFF_END_DT and
-- PERIOD_REFERENCE_TIME are linked to an unfed port (NULL).
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, CREATOR, USG_TP, LCTN_CRDNT_DESC, PSTL_BRCD, RGN_CD,
-- SRC_STATE (the source state port is unfed even though 'TX' goes to the validator), SRC_PSTL_CD_EXT,
-- ADDRESS_STATE, ADDRESS_ZIP_EXT, PERIOD_END_DATE, FLR_NUM (router port without input link).
-- DQM_ADDRESS.PTY_SRC_KEY tests SOURCE_TABLE = 'ECI_FAMILY' (copied from ECI), so it never gets the 'F' suffix.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_WIC_Pty_Addr (
    p_member_hierarchy_code  IN VARCHAR2 DEFAULT 'Member',        -- $Member_Hierarchy_Code
    p_member_hm_rel_tp_cd    IN VARCHAR2 DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_WIC_Pty_Addr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    sp_ors_helper01_common('C_S_WIC_PTY_RLE_ADDR');

    INSERT ALL
        -- Write_DQM_ADDRESS
        WHEN 1 = 1 THEN
            INTO DQM_ADDRESS
                 (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
                  LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
                  ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
                  MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
            VALUES (a_mailability_score, ADDRESS1, ADDRESS2, CITY, NULL, ZIP_CODE, 'US', COUNTY,
                    a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
                    a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
                    a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
                    fn_ors_helper07_common(a_result_percentage, 2), a_address_type, a_early_warning, a_cass_error,
                    a_dpv, '002', 'WIC', pkey_src_object, l_run_ts, LPAD(ID, 10, '0'), a_state_fips)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> exp_Address_Hold -> Write_C_S_WIC_PTY_RLE_ADDR
        WHEN score = '100' THEN
            INTO C_S_WIC_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  VERSION_SEQ, UPDATED_BY, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN, HM_REL_TP_CD, HUB_STATE_IND,
                  SRC_ROWID, USG_TP, HIERARCHY_CODE, ADDR_LN_1, ADDR_LN_2, SRC_LAST_UPD_DT, FLR_NUM, LCTN_CRDNT_DESC,
                  PSTL_BRCD, RGN_CD, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY,
                  SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT, ADDR_TP, PTY_RLE_FK, CREATE_DATE, CREATOR,
                  PERIOD_REFERENCE_TIME, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, COUNTY, MLBLTY_SCR, STATE,
                  RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM,
                  SUB_BLDG_DESC, BLDG_NMBR, PSTL_CD_EXT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, DATE_ADDRESS_VALID_FROM /* TIMELINE */,
                    1 /* TIMELINE: VERSION_SEQ */, c_mapping, l_run_ts, 'Primary',
                    TO_CHAR(ID) || '|' || TO_CHAR(FID), p_member_hm_rel_tp_cd, 1, pkey_src_object, NULL,
                    p_member_hierarchy_code, hold_line1, hold_line2, DATE_ADDRESS_VALID_FROM,
                    NULL /* FLR_NUM: router port unlinked */, NULL, NULL, NULL, ADDRESS1, ADDRESS2, CITY, COUNTY,
                    NULL, 'US', ZIP_CODE, NULL, DATE_ADDRESS_VALID_FROM /* TIMELINE */,
                    NULL /* TIMELINE: EFF_END_DT unfed */, '002', PTY_SRC_KEY || '|Member', DATE_ADDRESS_VALID_FROM,
                    NULL, NULL /* TIMELINE: PERIOD_REFERENCE_TIME unfed */, a_city, a_zip_cd_5, a_country,
                    a_match_code, a_latitude, a_longitude, a_county_fips, a_mailability_score, a_state_fips,
                    a_residential, a_org_descriptor, a_address_type, a_org_name, a_building_name, a_geocoding_status,
                    a_sub_building_complete, a_sub_building_descriptor, a_building_number, a_zip_cd_4_extn)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_US_Addr_Exc_Rec -> write_Exc_Member_Rec
        WHEN score = '40' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
                  EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES ('WIC', a_match_code, a_match_code_description, a_mailability_score,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN 'Address' END,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN
                         ADDRESS1 || ' ' || ADDRESS2 || ' ' || CITY || ' ' || NULL || ' ' || ZIP_CODE || ' ' || NULL
                         || ' ' || 'US' END,
                    c_mapping, '002', DATE_ADDRESS_VALID_FROM, NULL, 'Invalid_Address',
                    'Invalid Address per Address Doctor', l_run_ts, 'Bad Value', ADDRESS1, ADDRESS2, CITY, COUNTY,
                    NULL, ZIP_CODE, NULL, 'US', ID, FID, SOURCE_TABLE)
    WITH
    -- Read_V_WIC_ETL_SRC + Exp_src + Exp_Build_Src_key + Lookup_STG_WIC_PTY_INACTIVE_STS + Fil_Inactive_recs
    active AS (
        SELECT v.SOURCE_TABLE, v.ID, v.FID, v.DATE_ADDRESS_VALID_FROM, v.ADDRESS1, v.ADDRESS2, v.CITY, v.COUNTY,
               v.ZIP_CODE, v.PTY_SRC_KEY,
               v.PTY_SRC_KEY || '|Member' || '|' || '002' || '|' || LPAD(v.FID, 12, '0') || '|'
               || LTRIM(RTRIM(UPPER(v.ADDRESS1))) || '|' || LTRIM(RTRIM(UPPER(v.ADDRESS2))) || '|' || UPPER(v.CITY)
               || '|' || '|' || v.ZIP_CODE                                                       AS pkey_src_object
          FROM V_WIC_ETL_SRC v
         WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    -- Exp_all_active + mplt_Global_Addr_Validation
    validated AS (
        SELECT /*+ NO_MERGE */
               a.*,
               fn_dq_valid_global_addr(a.ADDRESS1, a.ADDRESS2, a.CITY, 'TX', a.ZIP_CODE, 'US', 'WIC') AS av
          FROM active a
    ),
    flat AS (
        SELECT v.*,
               v.av.delivery_address_line1          AS a_line1,
               v.av.delivery_address_line2          AS a_line2,
               v.av.city                            AS a_city,
               v.av.postcode_complete               AS a_postcode_complete,
               v.av.zip_cd_5                        AS a_zip_cd_5,
               v.av.zip_cd_4_extn                   AS a_zip_cd_4_extn,
               v.av.country_iso2_char               AS a_country,
               v.av.mailability_score               AS a_mailability_score,
               v.av.match_code                      AS a_match_code,
               v.av.match_code_description          AS a_match_code_description,
               v.av.status_info_result_percentage   AS a_result_percentage,
               v.av.address_type                    AS a_address_type,
               v.av.county_fips_cd                  AS a_county_fips,
               v.av.state_fips_cd                   AS a_state_fips,
               v.av.geocoding_latitude              AS a_latitude,
               v.av.geocoding_longitude             AS a_longitude,
               v.av.geocoding_status                AS a_geocoding_status,
               v.av.residential_delivery_indicator  AS a_residential,
               v.av.organization_name               AS a_org_name,
               v.av.organization_descriptor         AS a_org_descriptor,
               v.av.organization_department         AS a_org_department,
               v.av.building_complete               AS a_building_complete,
               v.av.building_name                   AS a_building_name,
               v.av.building_number                 AS a_building_number,
               v.av.sub_building_complete           AS a_sub_building_complete,
               v.av.sub_building_descriptor         AS a_sub_building_descriptor,
               v.av.early_warning_system_return_cd  AS a_early_warning,
               v.av.cass_error_code                 AS a_cass_error,
               v.av.dpv_confirmation                AS a_dpv
          FROM validated v
    )
    -- exp_Score_and_Exception_details + exp_Address_Hold
    SELECT f.*,
           fn_ors_helper09_common('002', f.a_mailability_score, f.a_match_code)  AS score,
           fn_ors_helper10_common('002', f.a_mailability_score, f.a_match_code)  AS addr_issue_desc,
           fn_ors_helper11_common(f.a_line1, f.a_line2)                         AS hold_line1,
           fn_ors_helper12_common(f.a_line1, f.a_line2)                         AS hold_line2
      FROM flat f;
    sp_ors_helper02_common(c_mapping, 'insert (DQM_ADDRESS, C_S_WIC_PTY_RLE_ADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_WIC_Pty_Addr;
/
