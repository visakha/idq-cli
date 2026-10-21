--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Addr (workflow wf_FSS_Stage_Load; copied from the ECI address
-- mapping).
--
-- Validates the FSS client addresses (V_FSS_ETL_SRC, capture action not 'D') and loads the good ones into
-- C_S_FSS_PTY_RLE_ADDR (insert only, never truncated):
--   -> Fil_Inactive_recs: party (PTY_SRC_KEY) not in STG_FSS_PTY_INACTIVE_STS
--   -> mplt_Global_Addr_Validation (fn_dq_valid_global_addr), zip without extension
--   -> Write_DQM_ADDRESS (every active address)
--   -> rtr_Good_vs_Exception_Pty_Records: Good ('100') -> C_S_FSS_PTY_RLE_ADDR; Exception ('40') -> EXC row
-- The address type is the constant '002' (physical mail), so the score depends only on the mailability score and
-- the match code.
--
-- TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DT_CREATED, EFF_STRT_DT = DT_LAST_UPDATE; EFF_END_DT and
-- PERIOD_REFERENCE_TIME are linked to an unfed port (NULL).
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, CREATOR, USG_TP, LCTN_CRDNT_DESC, PSTL_BRCD, RGN_CD,
-- SRC_PSTL_CD_EXT, ADDRESS_ZIP_EXT, PERIOD_END_DATE, FLR_NUM (router port without input link).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr (
    p_member_hierarchy_code  IN VARCHAR2 DEFAULT 'Member',        -- $Member_Hierarchy_Code
    p_member_hm_rel_tp_cd    IN VARCHAR2 DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_FSS_Pty_Addr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS
        WHEN 1 = 1 THEN
            INTO DQM_ADDRESS
                 (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
                  LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
                  ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
                  MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
            VALUES (a_mailability_score, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, ADDR_STATE, ADDR_ZIP, 'US', CD_CNTY,
                    a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
                    a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
                    a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
                    fn_ors_helper07_common(a_result_percentage, 2), a_address_type, a_early_warning, a_cass_error,
                    a_dpv, '002', 'FSS', pkey_src_object, l_run_ts, dqm_pty_src_key, a_state_fips)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> exp_Address_Hold -> Write_C_S_FSS_PTY_RLE_ADDR
        WHEN score = '100' THEN
            INTO C_S_FSS_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND,
                  PTY_RLE_FK, ADDR_TP, USG_TP, PREF_LVL, HIERARCHY_CODE, HM_REL_TP_CD, LOC_IDN, SRC_LAST_UPD_DT,
                  ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT,
                  LCTN_CRDNT_DESC, LATTD, LNGTD, PSTL_BRCD, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC,
                  ORG_NM, BLDG_NMBR, SUB_BLDG_NM, SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
                  SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT,
                  EFF_END_DT, PERIOD_START_DATE)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, 1 /* TIMELINE: VERSION_SEQ */,
                    NULL /* TIMELINE: PERIOD_REFERENCE_TIME, unfed */, l_run_ts, c_mapping, DT_LAST_UPDATE, NULL,
                    pkey_src_object, 1, PTY_SRC_KEY || '|Member', '002', NULL, 'Primary', p_member_hierarchy_code,
                    p_member_hm_rel_tp_cd, TO_CHAR(ID_CLIENT) || '|' || TO_CHAR(ID_REGISTRATION_CLIENT),
                    DT_LAST_UPDATE, hold_line1, hold_line2, a_building_name, NULL /* FLR_NUM: router port unlinked */,
                    a_city, a_county_fips, a_state_fips, a_country, a_zip_cd_5, a_zip_cd_4_extn, NULL, a_latitude,
                    a_longitude, NULL, a_match_code, NULL, a_mailability_score, a_address_type, a_org_descriptor,
                    a_org_name, a_building_number, a_sub_building_complete, a_sub_building_descriptor,
                    a_geocoding_status, a_residential, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE, 'US',
                    ADDR_ZIP, NULL, DT_LAST_UPDATE /* TIMELINE */, NULL /* TIMELINE: EFF_END_DT unfed */,
                    DT_CREATED /* TIMELINE */)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_US_Addr_Exc_Rec -> write_Exc_Member_Rec
        WHEN score = '40' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
                  EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES ('FSS', a_match_code, a_match_code_description, a_mailability_score,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN 'Address' END,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN
                         ADDR_LINE1 || ' ' || ADDR_LINE2 || ' ' || ADDR_CITY || ' ' || ADDR_STATE || ' ' || ADDR_ZIP
                         || ' ' || NULL || ' ' || 'US' END,
                    c_mapping, '002', DT_LAST_UPDATE, NULL, 'Invalid_Address', 'Invalid Address per Address Doctor',
                    l_run_ts, 'Bad Value', ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE, ADDR_ZIP, NULL,
                    'US', ID_CLIENT, ID_REGISTRATION_CLIENT, SOURCE_TYPE)
    WITH
    -- Read_V_FSS_ETL_SRC (source filter DTL__CAPXACTION <> 'D') + Exp_src + Exp_Build_Src_key
    src AS (
        SELECT v.SOURCE_TYPE, v.ID_CLIENT, v.ADDR_LINE1, v.ADDR_LINE2, v.ADDR_CITY, v.CD_CNTY, v.ADDR_ZIP,
               v.ADDR_STATE, v.PTY_SRC_KEY, v.ID_REGISTRATION_CLIENT, v.DT_LAST_UPDATE, v.DT_CREATED,
               v.PTY_SRC_KEY || '|Member' || '|' || '002' || '|' || LPAD(v.ID_REGISTRATION_CLIENT, 10, '0') || '|'
               || LTRIM(RTRIM(UPPER(v.ADDR_LINE1))) || '|' || LTRIM(RTRIM(UPPER(v.ADDR_LINE2))) || '|'
               || UPPER(v.ADDR_CITY) || '|' || UPPER(v.ADDR_STATE) || '|' || v.ADDR_ZIP              AS pkey_src_object,
               -- exp_Score_and_Exception_details.PTY_SRC_KEY (DQM_ADDRESS only)
               LPAD(v.ID_CLIENT, 10, '0') || CASE WHEN v.SOURCE_TYPE = 'FSS_FAMILY' THEN 'F' END  AS dqm_pty_src_key
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
        SELECT /*+ NO_MERGE */
               a.*,
               fn_dq_valid_global_addr(a.ADDR_LINE1, a.ADDR_LINE2, a.ADDR_CITY, a.ADDR_STATE, a.ADDR_ZIP, 'US',
                                       'FSS') AS av
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
    sp_ors_helper02_common(c_mapping, 'insert (DQM_ADDRESS, C_S_FSS_PTY_RLE_ADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr;
/
