--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Addr_2
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Addr_2 (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Part 2 of the TIERS address load: the individual addresses of the extract (latest create per individual / address
-- type / case / EDG) joined to the pre-validated unique addresses of m_Tgt_C_S_TRS_Addr_1 (STG_TRS_D_UNQ_ADDR) and to
-- the valid members:
--   -> Write_DQM_ADDRESS (every row)
--   -> lkp_Address_Type (V_LOOKUP_CODE_VALUE ADDR_TP, 'TRS') -> exp_Score_and_Exception_details
--   -> rtr_Good_vs_Exception_Pty_Records
--        Good ('100')     -> exp_Address_Hold -> srt_Party_Role_Addr_By_PKey_Beg_Date
--                            -> exp_Party_Role_Address_Attribute_Hold (VERSION_SEQ) -> C_S_TRS_PTY_RLE_ADDR (insert only)
--        Exception ('40') -> EXC_STG_BAD_REC_MEMB ('Invalid_Address', looked-up code)
--        Default          -> not linked (the score is always '40' or '100')
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * VERSION_SEQ is a running number per role-address key in (key, SRC_LAST_UPDATE_DATE desc, EFF_END_DT desc,
--     EFF_BEGIN_DT desc; NULL high) order - every row is written, numbered 1, 2, 3, ... within the key.
--   * SRC_ROWID = key || '|' || VERSION_SEQ.
--   * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set.
--   * PERIOD_END_DATE / EFF_END_DT = mplt_Date_Greater_Than_Fifty_Years(EFF_END_DT): NULL (open) when more than 50
--     years away.
--   * PERIOD_START_DATE / EFF_STRT_DT = EFF_BEGIN_DT.
-- The source's "select distinct" flag is ignored by IDQ when custom SQL is used, so it is not applied here either.
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, HUB_STATE_IND, USG_TP, CRDNT_SYS, PSTL_BRCD,
-- RGN_CD, CREATOR, CREATE_DATE, LCTN_CRDNT_DESC (sorter port without input).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Addr_2 (
    p_member_role_type       IN VARCHAR2 DEFAULT 'Member',        -- $Member_Role_Type
    p_member_hierarchy_code  IN VARCHAR2 DEFAULT 'Member',        -- $Member_Hierarchy_Code
    p_member_hm_rel_tp_cd    IN VARCHAR2 DEFAULT 'Member Addr'    -- $Member_HM_REL_TP_CD
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Addr_2';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_RLE_ADDR. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Write_DQM_ADDRESS (every row)
        WHEN 1 = 1 THEN
            INTO DQM_ADDRESS
                 (ADDR_SRC_KEY, SRC_SYSTEM, PTY_SRC_KEY, LOAD_DT, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_CNTRY,
                  RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_STATE, RSLT_CNTRY, COUNTY_FIPS, STATE_FIPS, LATTD, LNGTD,
                  RSLT_PSTL_CD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG, SUB_BLDG, MLBLTY_SCR, ADDRDR_MTCH_CD,
                  ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, RSLT_COUNTY, ORG_DEPT,
                  ORG_NM, SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, MDM_ADDR_TP)
            VALUES (ADDR_LN_1 || '|' || ADDR_LN_2 || '|' || CITY || '|' || rslt_pstl_cd || '|' || STATE || '|'
                    || CNTRY_CD, 'TRS', PTY_PK, l_run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_CNTRY, ADDR_LN_1,
                    ADDR_LN_2, CITY, STATE, CNTRY_CD, COUNTY, STATE, LATTD, LNGTD, rslt_pstl_cd, GEOCD_STS_CD,
                    RSDNTL_DLVRY_IND, ORG_DESC, BLDG_NMBR, SUB_BLDG_NM, MLBLTY_SCR, VLDTN_MSG, ERLY_WRNG_CD,
                    CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDR_TP_CD, COUNTY, ORG_DEPT, ORG_NM, SRC_COUNTY,
                    SRC_STATE, SRC_PSTL_CD || CASE WHEN SRC_PSTL_CD_EXT IS NOT NULL THEN '-' || SRC_PSTL_CD_EXT END,
                    ADDR_TYPE_CD)
        -- rtr_Good_vs_Exception_Pty_Records.Good -> ... -> Write_C_S_TRS_PTY_RLE_ADDR
        WHEN score = '100' THEN
            INTO C_S_TRS_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, HIERARCHY_CODE, HM_REL_TP_CD,
                  LAST_UPDATE_DATE, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, UPDATED_BY, SRC_ROWID,
                  HUB_STATE_IND, PREF_LVL, LOC_IDN, ADDR_TP, PTY_RLE_FK, USG_TP, ADDR_LN_1, ADDR_LN_2, CITY, PSTL_CD,
                  PSTL_CD_EXT, CNTRY_CD, CRDNT_SYS, LATTD, LNGTD, PSTL_BRCD, FLR_NUM, BLDNG_NM, COUNTY, STATE,
                  LCTN_CRDNT_DESC, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, GEOCD_STS_CD,
                  SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
                  SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, CREATOR, CREATE_DATE,
                  EFF_STRT_DT, PERIOD_END_DATE, EFF_END_DT)
            VALUES (pkey_pty_rle_addr, EFF_BEGIN_DT /* TIMELINE */, version_seq /* TIMELINE: running number */,
                    CASE WHEN EFF_END_DT IS NOT NULL THEN l_run_ts END /* TIMELINE */, p_member_hierarchy_code,
                    p_member_hm_rel_tp_cd, l_run_ts, NULL, NULL, NULL, NULL, NULL,
                    pkey_pty_rle_addr || '|' || TO_CHAR(version_seq) /* TIMELINE: versioned SRC_ROWID */, NULL,
                    'Primary', TO_CHAR(TRUNC(CASE_NUM)) || '|' || TO_CHAR(TRUNC(EDG_NUM)), mstr_addr_tp,
                    PTY_PK || '|' || p_member_role_type, NULL,
                    fn_ors_helper11_common(ADDR_LN_1, ADDR_LN_2), fn_ors_helper12_common(ADDR_LN_1, ADDR_LN_2), CITY,
                    PSTL_CD, PSTL_CD_EXT, CNTRY_CD, NULL, LATTD, LNGTD, NULL, FLR_NUM, BLDNG_NM, COUNTY, STATE,
                    NULL /* sorter port unfed */, VLDTN_MSG, NULL, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM,
                    GEOCD_STS_CD, SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
                    SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, CREATE_DT,
                    NULL, NULL, EFF_BEGIN_DT /* TIMELINE */, end_date_50y /* TIMELINE */, end_date_50y /* TIMELINE */)
        -- rtr_Good_vs_Exception_Pty_Records.Exception -> exp_TRS_US_Addr_Exc_Rec -> write_TRS_Exc_Member_Rec
        WHEN score = '40' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE, RUN_DATE,
                  ADDRESS_LINE_1, ADDRESS_LINE_2, ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP,
                  ADDRESS_ZIP_EXT, ADDRESS_COUNTRY, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES ('TRS', VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN 'Address' END,
                    CASE WHEN addr_issue_desc IS NOT NULL THEN
                         SRC_ADDR_LN_1 || ' ' || SRC_ADDR_LN_2 || ' ' || SRC_CITY || ' ' || SRC_STATE || ' '
                         || SRC_PSTL_CD || ' ' || SRC_PSTL_CD_EXT || ' ' || SRC_CNTRY END,
                    c_mapping, ADDR_TYPE_CD, EFF_BEGIN_DT, EFF_END_DT, l_run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2,
                    SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_CNTRY, INDV_ID, CASE_NUM,
                    EDG_NUM, fn_ors_helper08_common('Invalid_Address'), fn_ors_helper04_common('Invalid_Address'),
                    fn_ors_helper05_common('Invalid_Address'))
    WITH
    -- read_Staging_Delta_Tables (custom SQL, query mode SEMI)
    addr_de_dup AS (
        SELECT indv_id, case_num, edg_num, addr_type_cd,
               a.addr_st_num || '|' || a.addr_st_num_frac || '|' || a.addr_st_nm || '|' || addr_st_dir_cd || '|'
               || addr_st_type_cd || '|' || addr_dwelling_type_cd || '|' || a.addr_apt_num || '|' || a.addr_line || '|'
               || a.addr_city || '|' || a.addr_state_cd || '|' || a.addr_zip5 || '|' || a.addr_zip4 AS addr_id,
               GREATEST(create_dt, NVL(update_dt, create_dt)) create_dt, eff_begin_dt, eff_end_dt,
               ROW_NUMBER() OVER (PARTITION BY indv_id, addr_type_cd, case_num, edg_num
                                  ORDER BY GREATEST(create_dt, NVL(update_dt, create_dt)) DESC, eff_begin_dt DESC) key_rn
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
               u.dlvry_pnt_vldn AS DLVRY_PNT_VLDN, u.src_addr_ln_1 AS SRC_ADDR_LN_1, u.src_addr_ln_2 AS SRC_ADDR_LN_2,
               u.src_city AS SRC_CITY, u.src_county AS SRC_COUNTY, u.src_state AS SRC_STATE, u.src_cntry AS SRC_CNTRY,
               u.src_pstl_cd AS SRC_PSTL_CD, u.src_pstl_cd_ext AS SRC_PSTL_CD_EXT
          FROM addr_de_dup a
          JOIN stg_trs_d_unq_addr u ON a.addr_id = u.addr_id
          JOIN stg_trs_valid_members vm ON a.indv_id = vm.indv_id
         WHERE key_rn = 1
    ),
    -- lkp_Address_Type + Exp_src_defaults + exp_Address_Hold.PKEY_PTY_RLE_ADDR + mplt_Date_Greater_Than_Fifty_Years
    keyed AS (
        SELECT /*+ NO_MERGE */
               s.*,
               fn_ors_helper03_common('ADDR_TP', 'TRS', s.ADDR_TYPE_CD)                         AS mstr_addr_tp,
               s.PSTL_CD || CASE WHEN s.PSTL_CD_EXT IS NOT NULL THEN '-' || s.PSTL_CD_EXT END    AS rslt_pstl_cd,
               s.PTY_PK || '|' || p_member_role_type || '|'
               || fn_ors_helper03_common('ADDR_TP', 'TRS', s.ADDR_TYPE_CD) || '|' || TO_CHAR(s.CASE_NUM) || '|'
               || TO_CHAR(s.EDG_NUM) || '|' || TO_CHAR(s.EFF_BEGIN_DT, 'YYYYMMDD')                AS pkey_pty_rle_addr,
               fn_dq_date_within_50y(s.EFF_END_DT)                                                AS d50
          FROM src s
    )
    -- exp_Score_and_Exception_details + srt_Party_Role_Addr_By_PKey_Beg_Date + exp_Party_Role_Address_Attribute_Hold
    SELECT k.*,
           k.d50.out_date                                                                 AS end_date_50y,
           fn_ors_helper09_common(k.mstr_addr_tp, k.MLBLTY_SCR, k.VLDTN_MSG)              AS score,
           fn_ors_helper10_common(k.mstr_addr_tp, k.MLBLTY_SCR, k.VLDTN_MSG)              AS addr_issue_desc,
           ROW_NUMBER() OVER (PARTITION BY k.pkey_pty_rle_addr
                              ORDER BY k.CREATE_DT DESC NULLS FIRST, k.EFF_END_DT DESC NULLS FIRST,
                                       k.EFF_BEGIN_DT DESC NULLS FIRST)                   AS version_seq
      FROM keyed k;
    sp_ors_helper02_common(c_mapping, 'insert (DQM_ADDRESS, C_S_TRS_PTY_RLE_ADDR, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Addr_2;
/
