--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Addr_2
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Addr_2 (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Part 2 of the TIERS address load: the individual addresses of the extract (latest create per individual / address
-- type / case / EDG) joined to the pre-validated unique addresses of m_Tgt_C_S_TRS_Addr_1 (STG_TRS_D_UNQ_ADDR) and to
-- the valid members:
--   -> Write_DQM_ADDRESS (every row)
--   -> lkp_Address_Type (V_LOOKUP_CODE_VALUE ADDR_TP, 'TRS') -> exp_Score_and_Exception_details
--   -> rtr_Good_vs_Exception_Pty_Records
--        Good ('100')     -> exp_Address_Hold -> srt_Party_Role_Addr_By_PKey_Beg_Date
--                            -> exp_Party_Role_Address_Attribute_Hold (VERSION_SEQ) -> C_S_TRS_PTY_RLE_ADDR
--        Exception ('40') -> EXC_STG_BAD_REC_MEMB ('Invalid_Address', looked-up code)
--        Default          -> not linked (the score is always '40' or '100')
--
-- VALIDATION: address score (fn_snow_helper05_common) on the master address type, the mailability score and the
--   AddressDoctor match code of part 1 (VLDTN_MSG); an address type that does not translate scores '40'.
-- BAD DATA: an exception address is not loaded, only logged, with the looked-up code (NULL when 'Invalid_Address' is
--   not configured, docs/common_insights.md section 3). The source's "select distinct" flag is ignored by IDQ when
--   custom SQL is used, so it is not applied here either. Unfed ports written as NULL: ROWID_OBJECT, DELETED_*,
--   UPDATED_BY, HUB_STATE_IND, USG_TP, CRDNT_SYS, PSTL_BRCD, RGN_CD, CREATOR, CREATE_DATE, LCTN_CRDNT_DESC (sorter
--   port without input). Unique keys Snowflake does not enforce are applied: C_S_TRS_PTY_RLE_ADDR (PKEY_SRC_OBJECT,
--   VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE (stale MDM timeline, ported as IDQ does it; one of the three places where it is real):
--   * VERSION_SEQ is a running number per role-address key in (key, SRC_LAST_UPDATE_DATE desc, EFF_END_DT desc,
--     EFF_BEGIN_DT desc; NULL high) order - every row is written, numbered 1, 2, 3, ... within the key.
--   * SRC_ROWID = key || '|' || VERSION_SEQ.
--   * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set.
--   * PERIOD_END_DATE / EFF_END_DT = mplt_Date_Greater_Than_Fifty_Years(EFF_END_DT) (fn_snow_helper21_common): IDQ
--     compares the year difference as TEXT with '50', so end dates more than 50 years away AND end dates 6 to 10
--     years away become NULL (open) - docs/common_insights.md 1.15.
--   * PERIOD_START_DATE / EFF_STRT_DT = EFF_BEGIN_DT.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Addr_2 (
    P_MEMBER_ROLE_TYPE      VARCHAR DEFAULT 'Member',        -- $Member_Role_Type
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',        -- $Member_Hierarchy_Code
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Addr_2';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS (every row)
        WHEN TRUE THEN
            INTO DQM_ADDRESS
                 (ADDR_SRC_KEY, SRC_SYSTEM, PTY_SRC_KEY, LOAD_DT, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_CNTRY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_STATE, RSLT_CNTRY, COUNTY_FIPS, STATE_FIPS, LATTD, LNGTD,
                  RSLT_PSTL_CD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG, SUB_BLDG, MLBLTY_SCR, ADDRDR_MTCH_CD,
                  ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, RSLT_COUNTY, ORG_DEPT,
                  ORG_NM, SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, MDM_ADDR_TP)
            VALUES (dqm_addr_src_key, src_sys, PTY_PK, run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_CNTRY,
                    ADDR_LN_1, ADDR_LN_2, CITY, STATE, CNTRY_CD, COUNTY, STATE, LATTD, LNGTD, rslt_pstl_cd,
                    GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG_NMBR, SUB_BLDG_NM, MLBLTY_SCR, VLDTN_MSG,
                    ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDR_TP_CD, COUNTY, ORG_DEPT, ORG_NM,
                    SRC_COUNTY, SRC_STATE, dqm_src_pstl_cd, ADDR_TYPE_CD)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> ... -> Write_C_S_TRS_PTY_RLE_ADDR
        WHEN score = '100' AND uq_addr THEN
            INTO C_S_TRS_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, HIERARCHY_CODE, HM_REL_TP_CD,
                  LAST_UPDATE_DATE, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, UPDATED_BY, SRC_ROWID,
                  HUB_STATE_IND, PREF_LVL, LOC_IDN, ADDR_TP, PTY_RLE_FK, USG_TP, ADDR_LN_1, ADDR_LN_2, CITY, PSTL_CD,
                  PSTL_CD_EXT, CNTRY_CD, CRDNT_SYS, LATTD, LNGTD, PSTL_BRCD, FLR_NUM, BLDNG_NM, COUNTY, STATE,
                  LCTN_CRDNT_DESC, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, GEOCD_STS_CD,
                  SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
                  SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, CREATOR, CREATE_DATE,
                  EFF_STRT_DT, PERIOD_END_DATE, EFF_END_DT)
            VALUES (pkey_pty_rle_addr, EFF_BEGIN_DT, version_seq, period_reference_time, hierarchy_code, hm_rel_tp_cd,
                    run_ts, NULL, NULL, NULL, NULL, NULL, src_rowid, NULL, pref_lvl, loc_idn, mstr_addr_tp, pty_rle_fk,
                    NULL, hold_line1, hold_line2, CITY, PSTL_CD, PSTL_CD_EXT, CNTRY_CD, NULL, LATTD, LNGTD, NULL,
                    FLR_NUM, BLDNG_NM, COUNTY, STATE, NULL, VLDTN_MSG, NULL, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM,
                    GEOCD_STS_CD, SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
                    SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, CREATE_DT,
                    NULL, NULL, EFF_BEGIN_DT, end_date_50y, end_date_50y)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_TRS_US_Addr_Exc_Rec -> write_TRS_Exc_Member_Rec
        WHEN score = '40' AND uq_addr_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE, RUN_DATE,
                  ADDRESS_LINE_1, ADDRESS_LINE_2, ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP,
                  ADDRESS_ZIP_EXT, ADDRESS_COUNTRY, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES (src_sys, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, exc_attribute_name, exc_attribute_value, mapping_name,
                    ADDR_TYPE_CD, EFF_BEGIN_DT, EFF_END_DT, run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
                    SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_CNTRY, INDV_ID, CASE_NUM, EDG_NUM,
                    exc_code, exc_desc, exc_type)
    SELECT *
      FROM (
        WITH
        lkp_cv  AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- read_Staging_Delta_Tables (custom SQL, query mode SEMI)
        addr_de_dup AS (
            SELECT a.indv_id, a.case_num, a.edg_num, a.addr_type_cd,
                   NVL(TO_VARCHAR(a.addr_st_num), '') || '|' || NVL(a.addr_st_num_frac, '') || '|'
                   || NVL(a.addr_st_nm, '') || '|' || NVL(a.addr_st_dir_cd, '') || '|' || NVL(a.addr_st_type_cd, '')
                   || '|' || NVL(a.addr_dwelling_type_cd, '') || '|' || NVL(a.addr_apt_num, '') || '|'
                   || NVL(a.addr_line, '') || '|' || NVL(a.addr_city, '') || '|' || NVL(a.addr_state_cd, '') || '|'
                   || NVL(TO_VARCHAR(a.addr_zip5), '') || '|' || NVL(TO_VARCHAR(a.addr_zip4), '') AS addr_id,
                   GREATEST(a.create_dt, NVL(a.update_dt, a.create_dt)) AS create_dt, a.eff_begin_dt, a.eff_end_dt,
                   ROW_NUMBER() OVER (PARTITION BY a.indv_id, a.addr_type_cd, a.case_num, a.edg_num
                                      ORDER BY GREATEST(a.create_dt, NVL(a.update_dt, a.create_dt)) DESC,
                                               a.eff_begin_dt DESC) AS key_rn
              FROM STG_TRS_D_INDV_ADDR a
        ),
        src AS (
            SELECT a.indv_id AS INDV_ID, a.case_num AS CASE_NUM, a.edg_num AS EDG_NUM, vm.pty_pk AS PTY_PK,
                   a.addr_type_cd AS ADDR_TYPE_CD, a.create_dt AS CREATE_DT, a.eff_begin_dt AS EFF_BEGIN_DT,
                   a.eff_end_dt AS EFF_END_DT, u.addr_id AS ADDR_ID, u.addr_ln_1 AS ADDR_LN_1, u.addr_ln_2 AS ADDR_LN_2,
                   u.bldng_nm AS BLDNG_NM, u.flr_num AS FLR_NUM, u.city AS CITY, u.county AS COUNTY, u.state AS STATE,
                   u.cntry_cd AS CNTRY_CD, u.pstl_cd AS PSTL_CD, u.pstl_cd_ext AS PSTL_CD_EXT, u.lattd AS LATTD,
                   u.lngtd AS LNGTD, u.vldtn_msg AS VLDTN_MSG, u.vldtn_desc AS VLDTN_DESC, u.mlblty_scr AS MLBLTY_SCR,
                   u.addr_tp_cd AS ADDR_TP_CD, u.org_desc AS ORG_DESC, u.org_dept AS ORG_DEPT, u.org_nm AS ORG_NM,
                   u.bldg_nmbr AS BLDG_NMBR, u.sub_bldg_nm AS SUB_BLDG_NM, u.sub_bldg_desc AS SUB_BLDG_DESC,
                   u.geocd_sts_cd AS GEOCD_STS_CD, u.rsdntl_dlvry_ind AS RSDNTL_DLVRY_IND,
                   u.addrdr_rslt_pct AS ADDRDR_RSLT_PCT, u.erly_wrng_cd AS ERLY_WRNG_CD, u.cass_err_cd AS CASS_ERR_CD,
                   u.dlvry_pnt_vldn AS DLVRY_PNT_VLDN, u.src_addr_ln_1 AS SRC_ADDR_LN_1,
                   u.src_addr_ln_2 AS SRC_ADDR_LN_2, u.src_city AS SRC_CITY, u.src_county AS SRC_COUNTY,
                   u.src_state AS SRC_STATE, u.src_cntry AS SRC_CNTRY, u.src_pstl_cd AS SRC_PSTL_CD,
                   u.src_pstl_cd_ext AS SRC_PSTL_CD_EXT
              FROM addr_de_dup a
              JOIN STG_TRS_D_UNQ_ADDR u ON a.addr_id = u.addr_id
              JOIN STG_TRS_VALID_MEMBERS vm ON a.indv_id = vm.indv_id
             WHERE a.key_rn = 1
        ),
        -- lkp_Address_Type + Exp_src_defaults + exp_Address_Hold.PKEY_PTY_RLE_ADDR + mplt_Date_Greater_Than_Fifty_Years
        keyed AS (
            SELECT s.*,
                   at.MSTR_CODE_VALUE                                                                    AS mstr_addr_tp,
                   NVL(s.PSTL_CD, '') || IFF(s.PSTL_CD_EXT IS NOT NULL, '-' || s.PSTL_CD_EXT, '')         AS rslt_pstl_cd,
                   NVL(s.PTY_PK, '') || '|' || :P_MEMBER_ROLE_TYPE || '|' || NVL(at.MSTR_CODE_VALUE, '') || '|'
                   || NVL(TO_VARCHAR(s.CASE_NUM), '') || '|' || NVL(TO_VARCHAR(s.EDG_NUM), '') || '|'
                   || NVL(TO_VARCHAR(s.EFF_BEGIN_DT, 'YYYYMMDD'), '')                                    AS pkey_pty_rle_addr,
                   /* TIMELINE */ fn_snow_helper21_common(s.EFF_END_DT, :l_run_ts)                         AS end_date_50y
              FROM src s
              LEFT JOIN lkp_cv at ON at.CODE_TYPE = 'ADDR_TP' AND at.SRC_SYS = 'TRS' AND at.SRC_CODE_VALUE = s.ADDR_TYPE_CD
        ),
        -- exp_Score_and_Exception_details + srt_Party_Role_Addr_By_PKey_Beg_Date + exp_Party_Role_Address_Attribute_Hold
        scored AS (
            SELECT k.*,
                   /* VALIDATION */ fn_snow_helper05_common(k.mstr_addr_tp, k.MLBLTY_SCR, k.VLDTN_MSG)     AS score,
                   fn_snow_helper06_common(k.mstr_addr_tp, k.MLBLTY_SCR, k.VLDTN_MSG)                     AS addr_issue_desc,
                   /* TIMELINE */
                   ROW_NUMBER() OVER (PARTITION BY k.pkey_pty_rle_addr
                                      ORDER BY k.CREATE_DT DESC NULLS FIRST, k.EFF_END_DT DESC NULLS FIRST,
                                               k.EFF_BEGIN_DT DESC NULLS FIRST)                          AS version_seq
              FROM keyed k
        )
        SELECT c.*,
               'TRS'                                                                AS src_sys,
               :l_run_ts                                                            AS run_ts,
               :c_mapping                                                           AS mapping_name,
               :P_MEMBER_HIERARCHY_CODE                                             AS hierarchy_code,
               :P_MEMBER_HM_REL_TP_CD                                               AS hm_rel_tp_cd,
               'Primary'                                                            AS pref_lvl,
               /* TIMELINE */ IFF(c.EFF_END_DT IS NOT NULL, :l_run_ts, NULL)        AS period_reference_time,
               /* TIMELINE */ c.pkey_pty_rle_addr || '|' || TO_VARCHAR(c.version_seq) AS src_rowid,
               NVL(TO_VARCHAR(TRUNC(c.CASE_NUM)), '') || '|' || NVL(TO_VARCHAR(TRUNC(c.EDG_NUM)), '') AS loc_idn,
               NVL(c.PTY_PK, '') || '|' || :P_MEMBER_ROLE_TYPE                      AS pty_rle_fk,
               fn_snow_helper07_common(c.ADDR_LN_1, c.ADDR_LN_2)                    AS hold_line1,
               fn_snow_helper08_common(c.ADDR_LN_1, c.ADDR_LN_2)                    AS hold_line2,
               NVL(c.ADDR_LN_1, '') || '|' || NVL(c.ADDR_LN_2, '') || '|' || NVL(c.CITY, '') || '|' || c.rslt_pstl_cd
               || '|' || NVL(c.STATE, '') || '|' || NVL(c.CNTRY_CD, '')             AS dqm_addr_src_key,
               NVL(c.SRC_PSTL_CD, '') || IFF(c.SRC_PSTL_CD_EXT IS NOT NULL, '-' || c.SRC_PSTL_CD_EXT, '') AS dqm_src_pstl_cd,
               IFF(c.addr_issue_desc IS NOT NULL, 'Address', NULL)                  AS exc_attribute_name,
               IFF(c.addr_issue_desc IS NOT NULL,
                   NVL(c.SRC_ADDR_LN_1, '') || ' ' || NVL(c.SRC_ADDR_LN_2, '') || ' ' || NVL(c.SRC_CITY, '') || ' '
                   || NVL(c.SRC_STATE, '') || ' ' || NVL(TO_VARCHAR(c.SRC_PSTL_CD), '') || ' '
                   || NVL(TO_VARCHAR(c.SRC_PSTL_CD_EXT), '') || ' ' || NVL(c.SRC_CNTRY, ''), NULL) AS exc_attribute_value,
               ex.EXCEPTION_CODE                                                    AS exc_code,
               ex.EXCEPTION_DESC                                                    AS exc_desc,
               ex.EXCEPTION_TYPE                                                    AS exc_type,
               /* BAD DATA: unique keys Snowflake does not enforce */
               xa.PKEY_SRC_OBJECT IS NULL                                           AS uq_addr,
               ROW_NUMBER() OVER (PARTITION BY c.score, c.INDV_ID, c.CASE_NUM, c.EDG_NUM
                                      ORDER BY c.CREATE_DT DESC, c.ADDR_TYPE_CD) = 1 AS uq_addr_exc
          FROM scored c
          LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Address'
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_ADDR) xa
                 ON xa.PKEY_SRC_OBJECT = c.pkey_pty_rle_addr AND xa.VERSION_SEQ = c.version_seq
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (DQM_ADDRESS, C_S_TRS_PTY_RLE_ADDR, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
