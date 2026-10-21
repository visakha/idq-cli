--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Addr_1
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Addr_1 (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Part 1 of the TIERS address load: every UNIQUE address of the daily extract (STG_TRS_D_INDV_ADDR, distinct on the
-- address parts) goes through the address validator once (about a tenth of the volume), and every result, good or
-- bad, is written to the intermediate table STG_TRS_D_UNQ_ADDR (insert only, never truncated).
-- m_Tgt_C_S_TRS_Addr_2 joins it back to the individuals.
--   -> lkp_Addr_Street_Type (STG_TRS_CD_REF) + exp_TRS_Addr_Derivation:
--        line 1 = street number, fraction, direction (EA/NO/SO/WE abbreviated to the first letter, any case), street
--                 name, street type description
--        line 2 = dwelling type, apartment number, address line
--        zip    = zip5 || '-' || zip4
--   -> mplt_Global_Addr_Validation (fn_snow_helper34_common, with its lkp_State_Cd and lkp_ref_MatchCode_Desc)
--      -> Expression -> Write_STG_TRS_D_UNQ_ADDR
--
-- VALIDATION: the address validator (pass-through stand-in for AddressDoctor, README "Address validation"); the
--   score is computed later, in m_Tgt_C_S_TRS_Addr_2.
-- BAD DATA: the scrub rules clean the result lines; the derived source lines are kept in SRC_ADDR_LN_*. SRC_COUNTY is
--   linked to an unfed port (NULL). STG_TRS_D_UNQ_ADDR has primary key ADDR_ID, which Snowflake does not enforce;
--   IDQ truncates the table first, this code does not, so an address already validated in an earlier run is not
--   written again (the existing row is reused by part 2).
-- TIMELINE: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Addr_1 ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Addr_1';
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of STG_TRS_D_UNQ_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO STG_TRS_D_UNQ_ADDR
           (ADDR_ID, ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD,
            LNGTD, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, BLDG_NMBR, SUB_BLDG_NM,
            SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ADDRDR_RSLT_PCT, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT,
            ORG_DEPT)
    WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
    -- read_Staging_Delta_Tables (custom SQL, query mode SEMI, distinct)
    src AS (
        SELECT DISTINCT
               NVL(TO_VARCHAR(a.addr_st_num), '') || '|' || NVL(a.addr_st_num_frac, '') || '|' || NVL(a.addr_st_nm, '')
               || '|' || NVL(a.addr_st_dir_cd, '') || '|' || NVL(a.addr_st_type_cd, '') || '|'
               || NVL(a.addr_dwelling_type_cd, '') || '|' || NVL(a.addr_apt_num, '') || '|' || NVL(a.addr_line, '')
               || '|' || NVL(a.addr_city, '') || '|' || NVL(a.addr_state_cd, '') || '|' || NVL(TO_VARCHAR(a.addr_zip5), '')
               || '|' || NVL(TO_VARCHAR(a.addr_zip4), '')                                   AS ADDR_ID,
               a.addr_st_num AS ADDR_ST_NUM, a.addr_st_num_frac AS ADDR_ST_NUM_FRAC, a.addr_st_nm AS ADDR_ST_NM,
               a.addr_apt_num AS ADDR_APT_NUM, a.addr_line AS ADDR_LINE, a.addr_city AS ADDR_CITY,
               a.addr_state_cd AS ADDR_STATE_CD, a.addr_zip5 AS ADDR_ZIP5, a.addr_zip4 AS ADDR_ZIP4,
               a.addr_dwelling_type_cd AS ADDR_DWELLING_TYPE_CD, a.addr_st_type_cd AS ADDR_ST_TYPE_CD,
               a.addr_st_dir_cd AS ADDR_ST_DIR_CD
          FROM STG_TRS_D_INDV_ADDR a
    ),
    -- lkp_Addr_Street_Type (any row) + exp_TRS_Addr_Derivation
    derived AS (
        SELECT s.*,
               TRIM(NVL(TO_VARCHAR(s.ADDR_ST_NUM), '') || ' ' || NVL(s.ADDR_ST_NUM_FRAC, '') || ' '
                    || NVL(IFF(UPPER(s.ADDR_ST_DIR_CD) IN ('EA', 'NO', 'SO', 'WE'), SUBSTR(s.ADDR_ST_DIR_CD, 1, 1),
                               s.ADDR_ST_DIR_CD), '')
                    || ' ' || NVL(s.ADDR_ST_NM, '') || ' ' || NVL(st.DESCRIPTION, ''))                AS addr_line_1,
               TRIM(NVL(s.ADDR_DWELLING_TYPE_CD, '') || ' ' || NVL(s.ADDR_APT_NUM, '') || ' '
                    || NVL(s.ADDR_LINE, ''))                                                         AS addr_line_2
          FROM src s
          LEFT JOIN (SELECT r.CODE, r.DESCRIPTION FROM STG_TRS_CD_REF r
                     QUALIFY ROW_NUMBER() OVER (PARTITION BY r.CODE ORDER BY r.DESCRIPTION) = 1) st
                 ON st.CODE = s.ADDR_ST_TYPE_CD
    ),
    -- mplt_Global_Addr_Validation (lkp_State_Cd: V_LOOKUP_CODE_VALUE STATE, 'TRS')
    validated AS (
        SELECT d.*,
               fn_snow_helper34_common(d.addr_line_1, d.addr_line_2, d.ADDR_CITY, d.ADDR_STATE_CD,
                                       NVL(TO_VARCHAR(d.ADDR_ZIP5), '') || '-' || NVL(TO_VARCHAR(d.ADDR_ZIP4), ''),
                                       'US', stc.MSTR_CODE_VALUE) AS av
          FROM derived d
          LEFT JOIN lkp_cv stc ON stc.CODE_TYPE = 'STATE' AND stc.SRC_SYS = 'TRS'
                              AND stc.SRC_CODE_VALUE = UPPER(TRIM(d.ADDR_STATE_CD))
    )
    -- Expression
    SELECT v.ADDR_ID, v.av:delivery_address_line1::VARCHAR, v.av:delivery_address_line2::VARCHAR,
           v.av:building_name::VARCHAR, v.av:sub_building_number::VARCHAR, v.av:city::VARCHAR,
           v.av:county_fips_cd::VARCHAR, v.av:state_fips_cd::VARCHAR, v.av:country_iso2_char::VARCHAR,
           v.av:zip_cd_5::VARCHAR, v.av:zip_cd_4_extn::VARCHAR, v.av:geocoding_latitude::NUMBER(38, 6),
           v.av:geocoding_longitude::NUMBER(38, 6), v.av:match_code::VARCHAR, mc.DESCRIPTION,
           v.av:mailability_score::VARCHAR, v.av:address_type::VARCHAR, v.av:organization_descriptor::VARCHAR,
           v.av:organization_name::VARCHAR, v.av:building_number::VARCHAR, v.av:sub_building_complete::VARCHAR,
           v.av:sub_building_descriptor::VARCHAR, v.av:geocoding_status::VARCHAR,
           v.av:residential_delivery_indicator::VARCHAR, v.av:status_info_result_percentage::VARCHAR,
           v.av:early_warning_system_return_cd::VARCHAR, v.av:cass_error_code::VARCHAR,
           v.av:dpv_confirmation::VARCHAR, v.addr_line_1, v.addr_line_2, v.ADDR_CITY, NULL /* SRC_COUNTY unfed */,
           v.ADDR_STATE_CD, 'US', v.ADDR_ZIP5, v.ADDR_ZIP4, v.av:organization_department::VARCHAR
      FROM validated v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = v.av:status_info_match_code::VARCHAR
      /* BAD DATA: primary key ADDR_ID not yet in the table */
      LEFT JOIN (SELECT DISTINCT ADDR_ID FROM STG_TRS_D_UNQ_ADDR) xu ON xu.ADDR_ID = v.ADDR_ID
     WHERE xu.ADDR_ID IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY v.ADDR_ID ORDER BY v.addr_line_1) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert STG_TRS_D_UNQ_ADDR', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
