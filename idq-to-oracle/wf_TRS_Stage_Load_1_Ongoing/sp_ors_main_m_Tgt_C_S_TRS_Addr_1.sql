--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Addr_1
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Addr_1 (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Part 1 of the TIERS address load: every UNIQUE address of the daily extract (STG_TRS_D_INDV_ADDR, distinct on the
-- address parts) goes through the address validator once (about a tenth of the volume), and every result, good or
-- bad, is written to the intermediate table STG_TRS_D_UNQ_ADDR (insert only, never truncated). m_Tgt_C_S_TRS_Addr_2 joins it back
-- to the individuals.
--   -> lkp_Addr_Street_Type (STG_TRS_CD_REF) + exp_TRS_Addr_Derivation:
--        line 1 = street number, fraction, direction (EA/NO/SO/WE abbreviated to the first letter, any case), street
--                 name, street type description
--        line 2 = dwelling type, apartment number, address line
--        zip    = zip5 || '-' || zip4
--   -> mplt_Global_Addr_Validation (fn_dq_valid_global_addr) -> Expression -> Write_STG_TRS_D_UNQ_ADDR
--
-- Timeline: none. SRC_COUNTY is linked to an unfed port (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Addr_1
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Addr_1';
BEGIN
    -- Not performed: IDQ "truncate target table" of STG_TRS_D_UNQ_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO STG_TRS_D_UNQ_ADDR
           (ADDR_ID, ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD,
            LNGTD, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, BLDG_NMBR, SUB_BLDG_NM,
            SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ADDRDR_RSLT_PCT, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT,
            ORG_DEPT)
    WITH
    -- read_Staging_Delta_Tables (custom SQL, query mode SEMI, distinct)
    src AS (
        SELECT DISTINCT
               a.addr_st_num || '|' || a.addr_st_num_frac || '|' || a.addr_st_nm || '|' || addr_st_dir_cd || '|'
               || addr_st_type_cd || '|' || addr_dwelling_type_cd || '|' || a.addr_apt_num || '|' || a.addr_line || '|'
               || a.addr_city || '|' || a.addr_state_cd || '|' || a.addr_zip5 || '|' || a.addr_zip4 AS ADDR_ID,
               addr_st_num AS ADDR_ST_NUM, addr_st_num_frac AS ADDR_ST_NUM_FRAC, addr_st_nm AS ADDR_ST_NM,
               addr_apt_num AS ADDR_APT_NUM, addr_line AS ADDR_LINE, addr_city AS ADDR_CITY,
               addr_state_cd AS ADDR_STATE_CD, addr_zip5 AS ADDR_ZIP5, addr_zip4 AS ADDR_ZIP4,
               addr_dwelling_type_cd AS ADDR_DWELLING_TYPE_CD, addr_st_type_cd AS ADDR_ST_TYPE_CD,
               addr_st_dir_cd AS ADDR_ST_DIR_CD
          FROM STG_TRS_D_INDV_ADDR a
    ),
    -- lkp_Addr_Street_Type + exp_TRS_Addr_Derivation
    derived AS (
        SELECT s.*,
               LTRIM(RTRIM(s.ADDR_ST_NUM || ' ' || s.ADDR_ST_NUM_FRAC || ' '
                           || CASE WHEN UPPER(s.ADDR_ST_DIR_CD) IN ('EA', 'NO', 'SO', 'WE')
                                   THEN SUBSTR(s.ADDR_ST_DIR_CD, 1, 1) ELSE s.ADDR_ST_DIR_CD END
                           || ' ' || s.ADDR_ST_NM || ' ' || st.DESCRIPTION))                    AS addr_line_1,
               RTRIM(LTRIM(s.ADDR_DWELLING_TYPE_CD || ' ' || s.ADDR_APT_NUM || ' ' || s.ADDR_LINE)) AS addr_line_2
          FROM src s
         OUTER APPLY (SELECT r.DESCRIPTION FROM STG_TRS_CD_REF r
                       WHERE r.CODE = s.ADDR_ST_TYPE_CD FETCH FIRST 1 ROW ONLY) st
    ),
    validated AS (
        SELECT /*+ NO_MERGE */
               d.*,
               fn_dq_valid_global_addr(d.addr_line_1, d.addr_line_2, d.ADDR_CITY, d.ADDR_STATE_CD,
                                       d.ADDR_ZIP5 || '-' || d.ADDR_ZIP4, 'US', 'TRS') AS av
          FROM derived d
    )
    -- Expression
    SELECT v.ADDR_ID, v.av.delivery_address_line1, v.av.delivery_address_line2, v.av.building_name,
           v.av.sub_building_number, v.av.city, v.av.county_fips_cd, v.av.state_fips_cd, v.av.country_iso2_char,
           v.av.zip_cd_5, v.av.zip_cd_4_extn, v.av.geocoding_latitude, v.av.geocoding_longitude, v.av.match_code,
           v.av.match_code_description, v.av.mailability_score, v.av.address_type, v.av.organization_descriptor,
           v.av.organization_name, v.av.building_number, v.av.sub_building_complete, v.av.sub_building_descriptor,
           v.av.geocoding_status, v.av.residential_delivery_indicator, v.av.status_info_result_percentage,
           v.av.early_warning_system_return_cd, v.av.cass_error_code, v.av.dpv_confirmation,
           v.addr_line_1, v.addr_line_2, v.ADDR_CITY, NULL /* SRC_COUNTY unfed */, v.ADDR_STATE_CD, 'US',
           v.ADDR_ZIP5, v.ADDR_ZIP4, v.av.organization_department
      FROM validated v;
    sp_ors_helper02_common(c_mapping, 'insert STG_TRS_D_UNQ_ADDR', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Addr_1;
/
