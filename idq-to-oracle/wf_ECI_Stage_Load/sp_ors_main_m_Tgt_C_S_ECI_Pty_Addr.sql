--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Addr (workflow wf_ECI_Stage_Load).
--
-- Validates the ECI child and family addresses (V_ECI_ETL_SRC_FAMILY_ADDRESS) with the global address mapplet and
-- loads the good ones into C_S_ECI_PTY_RLE_ADDR (insert only, never truncated):
--   Read_V_ECI_ETL_SRC_FAMILY_ADDRESS -> lkp_Address_Type (V_LOOKUP_CODE_VALUE ADDR_TP)
--     -> Fil_Inactive_recs: party not in STG_ECI_PTY_INACTIVE_STS
--     -> mplt_Global_Addr_Validation (fn_dq_valid_global_addr)
--     -> exp_Score_and_Exception_details -> Write_DQM_ADDRESS        (every active address, before routing)
--     -> rtr_Good_vs_Exception_Pty_Records
--          Good      (Score = '100') -> exp_Address_Hold -> Write_C_S_ECI_PTY_RLE_ADDR
--          Exception (Score = '40')  -> write_ECI_Exc_Member_Rec (EXC_STG_BAD_REC_MEMB, 'Invalid_Address')
--          Default                   -> not linked (Score is always '40' or '100', so no row reaches it)
-- Score '40': address type not physical mail (002) and mailability <= '3'; physical mail with mailability < '3'
-- and a match code starting I/N; or an address type that does not translate. Comparisons are on strings, as in IDQ.
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * VERSION_SEQ = 1 (exp_Stage_Target_Party_Role_Addr_Attributes.VERSION_SEQ_NUM).
--   * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set; EFF_END_DT is not linked in IDQ, so it is NULL.
--   * PERIOD_START_DATE / EFF_STRT_DT = source LAST_UPDATE_DATE; EFF_END_DT NULL.
--
-- Ports linked to targets but fed by nothing in IDQ are written as NULL (ROWID_OBJECT, DELETED_*, CREATOR,
-- PSTL_BRCD, RGN_CD, LCTN_CRDNT_DESC, EFF_END_DT, PERIOD_END_DATE of the exception row, and FLR_NUM: the router port
-- Sub_buildingNumber has no input link in IDQ).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr (
    p_member_hierarchy_code  IN VARCHAR2 DEFAULT 'Member',        -- $Member_Hierarchy_Code
    p_member_hm_rel_tp_cd    IN VARCHAR2 DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty_Addr';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP() / $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS (all rows that pass Fil_Inactive_recs)
        WHEN 1 = 1 THEN
            INTO DQM_ADDRESS
                 (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
                  LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
                  ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
                  MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
            VALUES (a_mailability_score, ADDRESS1, ADDRESS2, CITY_NAME, STATE_ABBREV, ZIP_CODE, 'US', COUNTY_NAME,
                    a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
                    a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
                    a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
                    fn_ors_helper07_common(a_result_percentage, 2), a_address_type, a_early_warning, a_cass_error,
                    a_dpv, mstr_addr_tp, 'ECI', pkey_src_object, l_run_ts, pty_src_key, a_state_fips)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> exp_Address_Hold -> Write_C_S_ECI_PTY_RLE_ADDR
        WHEN score = '100' THEN
            INTO C_S_ECI_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  VERSION_SEQ, UPDATED_BY, CREATE_DATE, CREATOR, ADDR_TP, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN,
                  SRC_ROWID, HUB_STATE_IND, HIERARCHY_CODE, HM_REL_TP_CD, PERIOD_REFERENCE_TIME, ADDR_LN_1,
                  ADDR_LN_2, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, PSTL_BRCD, RGN_CD, COUNTY,
                  LCTN_CRDNT_DESC, MLBLTY_SCR, STATE, RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, FLR_NUM,
                  BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM, SUB_BLDG_DESC, BLDG_NMBR, SRC_ADDR_LN_1, SRC_ADDR_LN_2,
                  SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT,
                  PTY_RLE_FK, SRC_LAST_UPD_DT, PSTL_CD_EXT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, LAST_UPDATE_DATE /* TIMELINE */,
                    1 /* TIMELINE: VERSION_SEQ */, c_mapping, LAST_UPDATE_DATE, NULL, mstr_addr_tp, l_run_ts,
                    'Primary', TO_CHAR(TRUNC(ID)) || '|' || TO_CHAR(TRUNC(ID_FAMILY_ADDRESS)), pkey_src_object, 1,
                    p_member_hierarchy_code, p_member_hm_rel_tp_cd,
                    NULL /* TIMELINE: PERIOD_REFERENCE_TIME, EFF_END_DT unlinked */,
                    hold_line1, hold_line2, a_city, a_zip_cd_5, a_country, a_match_code, a_latitude, a_longitude,
                    NULL, NULL, a_county_fips, NULL, a_mailability_score, a_state_fips, a_residential,
                    a_org_descriptor, a_address_type, a_org_name, NULL /* FLR_NUM: router port unlinked */,
                    a_building_name, a_geocoding_status, a_sub_building_complete, a_sub_building_descriptor,
                    a_building_number, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, 'US', ZIP_CODE,
                    ZIP_SFX, LAST_UPDATE_DATE /* TIMELINE */, NULL /* TIMELINE: EFF_END_DT unlinked */,
                    pty_rle_fk, LAST_UPDATE_DATE, a_zip_cd_4_extn)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_ECI_US_Addr_Exc_Rec -> write_ECI_Exc_Member_Rec
        WHEN score = '40' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
                  EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES ('ECI', a_match_code, a_match_code_description, a_mailability_score,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN 'Address' END,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN
                         ADDRESS1 || ' ' || ADDRESS2 || ' ' || CITY_NAME || ' ' || STATE_ABBREV || ' ' || ZIP_CODE
                         || ' ' || ZIP_SFX || ' ' || 'US' END,
                    c_mapping, ADDRESS_CD, LAST_UPDATE_DATE, NULL, 'Invalid_Address',
                    'Invalid Address per Address Doctor', l_run_ts, 'Bad Value', ADDRESS1, ADDRESS2, CITY_NAME,
                    COUNTY_NAME, STATE_ABBREV, ZIP_CODE, ZIP_SFX, 'US', ID, ID_FAMILY_ADDRESS, SOURCE_TABLE)
    WITH
    -- Read_V_ECI_ETL_SRC_FAMILY_ADDRESS + Exp_src + lkp_Address_Type + Exp_Build_Src_key
    src AS (
        SELECT s.SOURCE_TABLE, s.ID, s.ID_FAMILY_ADDRESS, s.ADDRESS1, s.ADDRESS2, s.ADDRESS_CD, s.CITY_NAME,
               s.COUNTY_NAME, s.STATE_ABBREV, s.ZIP_CODE, s.ZIP_SFX, s.LAST_UPDATE_DATE,
               LPAD(s.ID, 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END             AS pty_src_key,
               LPAD(s.ID, 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END || '|Member' AS pty_rle_fk,
               fn_ors_helper03_common('ADDR_TP', 'ECI', s.ADDRESS_CD)                                 AS mstr_addr_tp
          FROM V_ECI_ETL_SRC_FAMILY_ADDRESS s
    ),
    keyed AS (
        SELECT s.*,
               s.pty_rle_fk || '|' || s.mstr_addr_tp || '|' || LPAD(s.ID_FAMILY_ADDRESS, 10, '0') || '|'
               || LTRIM(RTRIM(UPPER(s.ADDRESS1))) || '|' || LTRIM(RTRIM(UPPER(s.ADDRESS2))) || '|'
               || UPPER(s.CITY_NAME) || '|' || UPPER(s.STATE_ABBREV) || '|' || s.ZIP_CODE || '|' || s.ZIP_SFX
                                                                                                     AS pkey_src_object
          FROM src s
         -- Lkp_STG_ECI_PTY_INACTIVE_STS + Fil_Inactive_recs: IsNull(DEACTIVATION_STS)
         WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = s.pty_src_key AND i.ROWID_SYSTEM = 'ECI'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    -- Exp_all_active + mplt_Global_Addr_Validation
    validated AS (
        SELECT /*+ NO_MERGE */
               k.*,
               fn_dq_valid_global_addr(k.ADDRESS1, k.ADDRESS2, k.CITY_NAME, k.STATE_ABBREV,
                                       k.ZIP_CODE || CASE WHEN k.ZIP_SFX IS NOT NULL THEN '-' || k.ZIP_SFX END,
                                       'US', 'ECI') AS av
          FROM keyed k
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
           fn_ors_helper09_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code)  AS score,
           fn_ors_helper10_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code)  AS addr_issue_desc,
           fn_ors_helper11_common(f.a_line1, f.a_line2)                                  AS hold_line1,
           fn_ors_helper12_common(f.a_line1, f.a_line2)                                  AS hold_line2
      FROM flat f;
    sp_ors_helper02_common(c_mapping, 'insert (DQM_ADDRESS, C_S_ECI_PTY_RLE_ADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr;
/
