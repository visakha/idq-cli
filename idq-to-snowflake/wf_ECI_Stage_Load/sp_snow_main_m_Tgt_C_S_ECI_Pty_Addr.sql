--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Addr (workflow wf_ECI_Stage_Load).
--
-- Validates the ECI child and family addresses (V_ECI_ETL_SRC_FAMILY_ADDRESS) with the global address mapplet and
-- loads the good ones into C_S_ECI_PTY_RLE_ADDR (insert only, never truncated):
--   Read_V_ECI_ETL_SRC_FAMILY_ADDRESS -> lkp_Address_Type (V_LOOKUP_CODE_VALUE ADDR_TP)
--     -> Fil_Inactive_recs: party not in STG_ECI_PTY_INACTIVE_STS
--     -> mplt_Global_Addr_Validation (fn_snow_helper34_common, with its lkp_State_Cd and lkp_ref_MatchCode_Desc)
--     -> exp_Score_and_Exception_details -> Write_DQM_ADDRESS        (every active address, before routing)
--     -> rtr_Good_vs_Exception_Pty_Records
--          Good      (Score = '100') -> exp_Address_Hold -> Write_C_S_ECI_PTY_RLE_ADDR
--          Exception (Score = '40')  -> write_ECI_Exc_Member_Rec (EXC_STG_BAD_REC_MEMB, 'Invalid_Address')
--          Default                   -> not linked (Score is always '40' or '100', so no row reaches it)
--
-- VALIDATION: Score '40' (fn_snow_helper05_common): address type not physical mail (002) and mailability <= '3';
--   physical mail with mailability < '3' and a match code starting I / N; or an address type that does not
--   translate. Comparisons are on strings, as in IDQ. The address validator is the pass-through stand-in for
--   AddressDoctor (README, "Address validation"): mailability and match code are NULL, so every address with a
--   known type scores '100'.
-- BAD DATA: an exception address is not loaded, only logged, with the hard-coded description 'Invalid Address per
--   Address Doctor' and type 'Bad Value' (no EXC_LOOKUP_CODE_VALUE lookup in this mapping). The scrub rules clean
--   the result lines; the source lines are kept in SRC_ADDR_LN_*. Ports linked to targets but fed by nothing in IDQ
--   are written as NULL (ROWID_OBJECT, DELETED_*, CREATOR, PSTL_BRCD, RGN_CD, LCTN_CRDNT_DESC, EFF_END_DT, the
--   exception PERIOD_END_DATE, and FLR_NUM: the router port Sub_buildingNumber has no input link). Unique keys
--   Snowflake does not enforce are applied: C_S_ECI_PTY_RLE_ADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB.
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * VERSION_SEQ = 1 (exp_Stage_Target_Party_Role_Addr_Attributes.VERSION_SEQ_NUM).
--   * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set; EFF_END_DT is not linked in IDQ, so it is NULL.
--   * PERIOD_START_DATE / EFF_STRT_DT = source LAST_UPDATE_DATE; EFF_END_DT NULL.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr (
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',        -- $Member_Hierarchy_Code
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_Addr';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP() / $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS (all rows that pass Fil_Inactive_recs)
        WHEN TRUE THEN
            INTO DQM_ADDRESS
                 (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
                  LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
                  ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
                  MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
            VALUES (a_mailability_score, ADDRESS1, ADDRESS2, CITY_NAME, STATE_ABBREV, ZIP_CODE, src_cntry, COUNTY_NAME,
                    a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
                    a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
                    a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
                    a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, mstr_addr_tp, src_sys,
                    pkey_src_object, run_ts, pty_src_key, a_state_fips)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> exp_Address_Hold -> Write_C_S_ECI_PTY_RLE_ADDR
        WHEN score = '100' AND uq_addr THEN
            INTO C_S_ECI_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  VERSION_SEQ, UPDATED_BY, CREATE_DATE, CREATOR, ADDR_TP, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN,
                  SRC_ROWID, HUB_STATE_IND, HIERARCHY_CODE, HM_REL_TP_CD, PERIOD_REFERENCE_TIME, ADDR_LN_1,
                  ADDR_LN_2, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, PSTL_BRCD, RGN_CD, COUNTY,
                  LCTN_CRDNT_DESC, MLBLTY_SCR, STATE, RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, FLR_NUM,
                  BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM, SUB_BLDG_DESC, BLDG_NMBR, SRC_ADDR_LN_1, SRC_ADDR_LN_2,
                  SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT,
                  PTY_RLE_FK, SRC_LAST_UPD_DT, PSTL_CD_EXT)
            VALUES (pkey_src_object, NULL, NULL, NULL, NULL, LAST_UPDATE_DATE, version_seq, mapping_name,
                    LAST_UPDATE_DATE, NULL, mstr_addr_tp, run_ts, pref_lvl, loc_idn, pkey_src_object, hub_state_ind,
                    hierarchy_code, hm_rel_tp_cd, NULL, hold_line1, hold_line2, a_city, a_zip_cd_5, a_country,
                    a_match_code, a_latitude, a_longitude, NULL, NULL, a_county_fips, NULL, a_mailability_score,
                    a_state_fips, a_residential, a_org_descriptor, a_address_type, a_org_name, NULL,
                    a_building_name, a_geocoding_status, a_sub_building_complete, a_sub_building_descriptor,
                    a_building_number, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, src_cntry, ZIP_CODE,
                    ZIP_SFX, LAST_UPDATE_DATE, NULL, pty_rle_fk, LAST_UPDATE_DATE, a_zip_cd_4_extn)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_ECI_US_Addr_Exc_Rec -> write_ECI_Exc_Member_Rec
        WHEN score = '40' AND uq_addr_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
                  EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
            VALUES (src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
                    exc_attribute_value, mapping_name, ADDRESS_CD, LAST_UPDATE_DATE, NULL, exc_code, exc_desc,
                    run_ts, exc_type, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, ZIP_CODE, ZIP_SFX,
                    src_cntry, ID, ID_FAMILY_ADDRESS, SOURCE_TABLE)
    SELECT *
      FROM (
        WITH
        lkp_cv  AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_mc  AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
        -- Read_V_ECI_ETL_SRC_FAMILY_ADDRESS + Exp_src + lkp_Address_Type + Exp_Build_Src_key
        src AS (
            SELECT s.SOURCE_TABLE, s.ID, s.ID_FAMILY_ADDRESS, s.ADDRESS1, s.ADDRESS2, s.ADDRESS_CD, s.CITY_NAME,
                   s.COUNTY_NAME, s.STATE_ABBREV, s.ZIP_CODE, s.ZIP_SFX, s.LAST_UPDATE_DATE,
                   LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')   AS pty_src_key,
                   LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '') || '|Member'
                                                                                                   AS pty_rle_fk,
                   at.MSTR_CODE_VALUE                                                              AS mstr_addr_tp
              FROM V_ECI_ETL_SRC_FAMILY_ADDRESS s
              LEFT JOIN lkp_cv at ON at.CODE_TYPE = 'ADDR_TP' AND at.SRC_SYS = 'ECI'
                                 AND at.SRC_CODE_VALUE = s.ADDRESS_CD
        ),
        keyed AS (
            SELECT s.*,
                   s.pty_rle_fk || '|' || NVL(s.mstr_addr_tp, '') || '|'
                   || NVL(LPAD(TO_VARCHAR(s.ID_FAMILY_ADDRESS), 10, '0'), '') || '|'
                   || NVL(TRIM(UPPER(s.ADDRESS1)), '') || '|' || NVL(TRIM(UPPER(s.ADDRESS2)), '') || '|'
                   || NVL(UPPER(s.CITY_NAME), '') || '|' || NVL(UPPER(s.STATE_ABBREV), '') || '|'
                   || NVL(s.ZIP_CODE, '') || '|' || NVL(s.ZIP_SFX, '')                             AS pkey_src_object
              FROM src s
             -- Lkp_STG_ECI_PTY_INACTIVE_STS + Fil_Inactive_recs: IsNull(DEACTIVATION_STS)
             WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = s.pty_src_key AND i.ROWID_SYSTEM = 'ECI'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        -- Exp_all_active + mplt_Global_Addr_Validation (lkp_State_Cd: V_LOOKUP_CODE_VALUE STATE)
        validated AS (
            SELECT k.*,
                   fn_snow_helper34_common(k.ADDRESS1, k.ADDRESS2, k.CITY_NAME, k.STATE_ABBREV,
                                           NVL(k.ZIP_CODE, '') || IFF(k.ZIP_SFX IS NOT NULL, '-' || k.ZIP_SFX, ''),
                                           'US', st.MSTR_CODE_VALUE) AS av
              FROM keyed k
              LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'ECI'
                                 AND st.SRC_CODE_VALUE = UPPER(TRIM(k.STATE_ABBREV))
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
                   /* VALIDATION */ fn_snow_helper05_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code) AS score,
                   fn_snow_helper06_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
                   fn_snow_helper07_common(f.a_line1, f.a_line2)                                   AS hold_line1,
                   fn_snow_helper08_common(f.a_line1, f.a_line2)                                   AS hold_line2
              FROM flat f
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
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY s.score, s.pkey_src_object
                                       ORDER BY s.LAST_UPDATE_DATE DESC, s.ID_FAMILY_ADDRESS) = 1
                AND xa.PKEY_SRC_OBJECT IS NULL)                              AS uq_addr,
               ROW_NUMBER() OVER (PARTITION BY s.score, s.ID, s.ID_FAMILY_ADDRESS, s.SOURCE_TABLE
                                      ORDER BY s.LAST_UPDATE_DATE DESC) = 1  AS uq_addr_exc
          FROM scored s
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xa
                 ON xa.PKEY_SRC_OBJECT = s.pkey_src_object
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (DQM_ADDRESS, C_S_ECI_PTY_RLE_ADDR, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
