--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_CRE_CARE_Clients (workflow wf_CRE_Stage_Load_Ongoing, its
-- only mapping).
--
-- Loads the CARE clients into CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN and
-- C_S_CRE_PTY_RLE_ALT_ID (insert only, never truncated) and logs exceptions:
--   -> custom SQL: new and changed clients ('I'), deleted ('D') and moved ('B') cases from the snapshot
--      STG_CRE_SN_CARE_CLIENTS through STG_CRE_D_CARE_CASE_MAINT, the targets of the moves ('A')
--   -> RTR_MERGES: rows that are not regular or deleted (DELETES group) look the source and target CARE ids up in
--      C_B_PTY_XREF and their original records in C_B_PTY_HMRG; no merge history at all -> CRE_SRC_MRG
--   -> name standardization; a member needs a standardized first AND last name, otherwise the missing name is logged
--   -> one row per CARE id (REC_TYPE descending: I, D, B, A) -> party, role, address (US: address validation; abroad:
--      state 99, country ZZ), phone, and the three alternate ids (CARE ID, Medicaid ID, SSN)
--
-- VALIDATION: fn_snow_helper15_common (name, with the SUFFIX and junk-name lookups), fn_snow_helper17_common
--   (gender), fn_snow_helper18_common with V_LOOKUP_CODE_VALUE ETHNICITY / RACE, fn_snow_helper23/24_common (phone,
--   only the number linked: no toll-free check for CRE), fn_snow_helper27_common (Medicaid id),
--   fn_snow_helper26_common (SSN), fn_snow_helper37_common (CARE id), fn_snow_helper34_common (address) and
--   RTR_VALID_ADDRESS: (TO_INTEGER(mailability score) >= 3 OR match code not starting I / N) AND a state FIPS; abroad
--   the city and street must be present. No birth-date rule. The name, phone and SSN routes and the address, gender,
--   ethnicity and race exception rows use the code AS LOOKED UP in EXC_LOOKUP_CODE_VALUE (fn_snow_helper40_common):
--   unconfigured means no name row, a loaded phone or SSN, an address row with a NULL code, no gender / ethnicity /
--   race row. The suffix and Medicaid rows write the computed code.
-- BAD DATA: invalid members are logged and dropped; a bad address, phone or alternate id is logged instead of loaded
--   (the member itself is loaded); SSN 'U' / 'N' blanked and dropped; ids lose special characters and are cut to 10
--   characters; phones are cut to 10 digits; SRC_ROWID is cut to 30 characters (IDQ truncates to the target
--   precision); with the pass-through validator (no score, no match code) the RTR_VALID_ADDRESS condition is NULL, so
--   every US address is an exception. Unique keys Snowflake does not enforce are applied: the C_S_* targets
--   (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB (the name rows of a CARE id read twice, and the Medicaid
--   and SSN rows that the source and the target of an unmerged move both log under the target id).
-- TIMELINE: VERSION_SEQ = VERSION_SEQ_NUM (the rank per CARE id; 1 for every written row). 'B' and 'D' rows are
--   end-dated: PERIOD_START_DATE = CARE_LASTUP_DT - 1 day, PERIOD_END_DATE = CARE_LASTUP_DT, TIMELINE_ACTION = 2,
--   PERIOD_REFERENCE_TIME = PERIOD_START_DATE, LAST_UPDATE_DATE = run start - 1 hour (the role keeps the run start).
--   The role and the alternate ids do not link TIMELINE_ACTION / PERIOD_REFERENCE_TIME (written NULL).
--   IDQ quirks kept: CRE_SRC_MRG also gets moves whose CARE ids have no cross-reference (NULL records), and the move
--   target row again when it carries a MAINT_FLAG; the CARE ID alternate id of an unmerged move is the target id; the
--   state and alternate-id type lookups have no code-type filter (fn_snow_helper42_common / LOOKUP_CODE_VALUE by
--   source value), so an untranslated type leaves ALT_ID_TP and the exception's SRC_SYS NULL.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients (
    P_PHYSICAL_ADDR_TYPE_CD  VARCHAR DEFAULT '002',      -- $PHYSICAL_ADDR_TYPE_CD
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',   -- $RLE_BO_CLASS_CD_Member
    P_DEFAULT_TX_STATE_CD    VARCHAR DEFAULT '48',       -- $Default_TX_State_CD
    P_COUNTY_CD_NONTX        VARCHAR DEFAULT '996',      -- $County_CD_NonTX
    P_COUNTYCD_DEFAULTALL    VARCHAR DEFAULT '998',      -- $CountyCD_DefaultAll
    P_DEFAULT_NONUS_STATE_CD VARCHAR DEFAULT '99'        -- $Default_NonUS_State_CD
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_CRE_CARE_Clients';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SESSSTARTTIME / SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN, C_S_CRE_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- RTR_MERGES.Default -> FLTR_CRE_MRG -> Write_CRE_SRC_MRG
        WHEN grp_mrg THEN
            INTO CRE_SRC_MRG (SRC_ROWID_OBJECT, TGT_ROWID_OBJECT, RUN_DATE)
            VALUES (src_rowid_object, tgt_rowid_object, run_ts)
        -- rtr_Invalid_First_Last_Name.FirstName_Issue -> Write_EXC_STG_BAD_REC_MEMB_FName
        WHEN grp_first_name AND uq_first_name THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_1, RUN_DATE, MAPPING_NAME, FIRST_NAME, LAST_NAME, ATTRIBUTE_NAME, GENDER, BIRTH_DATE,
                  SUFFIX, SRC_SYS, ATTRIBUTE_VALUE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
            VALUES (CARE_ID, run_ts, mapping_name, std_first_name, std_lst_name, attr_first_name, SEX, BIRTH_DT,
                    std_sfx_name, src_sys, FIRSTNM, fn_exception_type, fn_exception_desc, fn_exception_code)
        -- rtr_Invalid_First_Last_Name.LastName_Issue -> exp_Last_Name_Exception -> Write_EXC_STG_BAD_REC_MEMB_LName
        WHEN grp_last_name AND uq_last_name THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, FIRST_NAME, MAPPING_NAME, BIRTH_DATE, GENDER, ADDRESS_LINE_1,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ATTRIBUTE_NAME, LAST_NAME,
                  SUFFIX, ATTRIBUTE_VALUE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES (src_sys, CARE_ID, run_ts, std_first_name, mapping_name, BIRTH_DT, SEX, STREET, CITY, CNTY, STATE,
                    ZIP, ZIPSUF, attr_last_name, std_lst_name, std_sfx_name, LASTNM, ln_exception_code,
                    ln_exception_desc, ln_exception_type)
        -- Filt_DeDeup_Seq1 -> EXP_PTY -> EXP_PTY_HOLD -> SRT_MRG_RECORDS -> Write_C_S_CRE_PTY
        WHEN is_member AND uq_pty THEN
            INTO C_S_CRE_PTY
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME,
                  TIMELINE_ACTION, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, BIRTH_DT, FULL_NM, GNDR_CD, SFX_NM,
                  LST_NM, FRST_NM, PTY_BO_CLASS_CD, SRC_FULL_NM, SRC_LAST_UPD_DT, ETHNCTY, RACE_CD, SRC_ETHNCTY,
                  SRC_RACE_CD)
            VALUES (pty_key, period_start, pty_period_end, version_seq_num, pty_period_reference_time,
                    timeline_action, last_update, last_update, pty_key, BIRTH_DT, std_full_name, mdm_gender_code,
                    std_sfx_name, std_lst_name, std_first_name, pty_bo_class_cd, std_src_full_name, src_last_update,
                    ethnicity_mstr, race_mstr, FEDETH, RACE)
        -- EXP_PTY_RLE_HOLD -> Write_C_S_CRE_PTY_RLE
        WHEN is_member AND uq_rle THEN
            INTO C_S_CRE_PTY_RLE
                 (PTY_FK, PKEY_SRC_OBJECT, SRC_ROWID, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ,
                  LAST_UPDATE_DATE, RLE_BO_CLASS_CD, CREATE_DATE, SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME,
                  TIMELINE_ACTION)
            VALUES (pty_key, rle_key, rle_key, period_start, pty_period_end, version_seq_num, run_ts,
                    rle_bo_class_cd, run_ts, src_last_update, null_timestamp, null_number)
        -- fltr_Gender_Exc -> Exp_Write_Gender_Exc -> Write_EXC_STG_BAD_REC_MEMB_Gender_Cd
        WHEN grp_gender THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
                  EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC)
            VALUES (src_sys, CARE_ID, run_ts, SEX, attr_gender, SEX, mapping_name, gender_exception_type,
                    gender_exception_code, gender_exception_description)
        -- fltr_Suffix_exc -> Exp_Write_Suffix_Exc -> Write_EXC_STG_BAD_REC_MEMB_Suffix
        WHEN grp_suffix THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, MAPPING_NAME)
            VALUES (src_sys, CARE_ID, suffix_exception_type, suffix_exception_code, suffix_exception_desc, run_ts,
                    attr_suffix, src_suffix, mapping_name)
        -- Filt_Bad_Ethnicity_Cd -> Write_EXC_STG_BAD_REC_MEMB_Ethnicity_Cd
        WHEN grp_ethnicity THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, EXCEPTION_CODE,
                  EXCEPTION_TYPE, EXCEPTION_DESC)
            VALUES (src_sys, pty_key, run_ts, attr_fedeth, FEDETH, mapping_name, ethnicity_exception_code,
                    ethnicity_exception_type, ethnicity_exception_desc)
        -- Filt_Bad_Race_Cd -> Write_EXC_STG_BAD_REC_MEMB_Race_Cd
        WHEN grp_race THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, EXCEPTION_TYPE,
                  EXCEPTION_DESC, EXCEPTION_CODE)
            VALUES (src_sys, pty_key, run_ts, attr_race, RACE, mapping_name, race_exception_type, race_exception_desc,
                    race_exception_code)
        -- UNION_ADDRESSES -> EXP_PTY_RLE_ADDR_HOLD -> Write_C_S_CRE_PTY_RLE_ADDR
        WHEN grp_addr AND uq_addr THEN
            INTO C_S_CRE_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, LAST_UPDATE_DATE, PERIOD_START_DATE, PERIOD_END_DATE,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, CREATE_DATE, HIERARCHY_CODE, PREF_LVL, ADDR_TP, HM_REL_TP_CD,
                  ADDR_LN_1, ADDR_LN_2, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD, LNGTD, MLBLTY_SCR,
                  PTY_RLE_FK, USG_TP, SRC_ADDR_LN_1, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD,
                  SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, FLR_NUM, ADDR_TP_CD, SUB_BLDG_DESC, SUB_BLDG_NM, BLDG_NMBR,
                  BLDNG_NM, RSDNTL_DLVRY_IND, GEOCD_STS_CD, ORG_NM, ORG_DESC, VLDTN_MSG)
            VALUES (addr_key, addr_src_rowid, version_seq_num, last_update, period_start, period_end,
                    period_reference_time, timeline_action, last_update, hierarchy_code, pref_lvl, addr_tp,
                    hm_rel_tp_cd, a_line1, a_line2, a_city, a_county, a_state, a_country, a_postcode, a_postcode_ext,
                    a_latitude, a_longitude, a_mailability_score, rle_key, addr_tp, STREET, CITY, CNTY, STATE,
                    src_cntry, ZIP, ZIPSUF, CARE_LASTUP_DT, a_sub_building_number, a_address_type,
                    a_sub_building_descriptor, a_sub_building_complete, a_building_number, a_building_name,
                    a_residential, a_geocoding_status, a_org_name, a_org_descriptor, a_match_code)
        -- UNION_INVALID_ADDRESSES -> Lkp_EXC_LOOKUP_CODE_VALUE -> Write_EXC_STG_BAD_REC_MEMB_ADDR
        WHEN grp_addr_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, ADDRESS_DR_MAILABILITY_SCORE, ADDRESS_DR_ERROR_DESC,
                  ADDRESS_DR_ERROR_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1, ADDRESS_LINE_1, ADDRESS_CITY,
                  ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES (src_sys, run_ts, mapping_name, a_dr_mailability_score, a_dr_error_desc, a_dr_error_code,
                    attr_address, addr_attribute_value, CARE_ID, STREET, CITY, CNTY, STATE, ZIP, ZIPSUF, src_cntry,
                    addr_exception_code, addr_exception_desc, addr_exception_type)
        -- RTR_VALID_PHONE.VALID -> EXP_PTY_RLE_PHN_HOLD -> Write_C_S_CRE_PTY_RLE_PHN
        WHEN grp_phone AND uq_phone THEN
            INTO C_S_CRE_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, SRC_ROWID, PHN_NUM, VERSION_SEQ, LAST_UPDATE_DATE, PHN_TP, PTY_RLE_FK, USG_TP,
                  PREF_LVL, PERIOD_START_DATE, PERIOD_END_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, CREATE_DATE,
                  SRC_LAST_UPD_DT)
            VALUES (phn_key, phn_src_rowid, phone_std, version_seq_num, last_update, phn_tp, member_rle_fk,
                    usg_tp_phone, pref_lvl, period_start, period_end, timeline_action, period_reference_time,
                    last_update, CARE_LASTUP_DT)
        -- RTR_VALID_PHONE.Default -> EXP_PTY_RLE_PHN_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_PHONE
        WHEN grp_phone_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, PRIMARY_PHONE, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1,
                  EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC)
            VALUES (src_sys, phone_std, mapping_name, run_ts, attr_phone, phone_std, CARE_ID, phone_exception_code,
                    phone_exception_type, phone_exception_desc)
        -- NRML_ALT_ID CARE ID -> RTR_VALID_ALT_ID.VALID_ALT_ID -> EXP_ALT_ID_SET_PKEY -> Write_C_S_CRE_PTY_RLE_ALT_ID
        WHEN grp_care_alt AND uq_care_alt THEN
            INTO C_S_CRE_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
                  ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
                  TIMELINE_ACTION)
            VALUES (care_alt_key, period_start, period_end, version_seq_num, rle_key, care_tp_cd, care_alt_val,
                    care_tp_cd, sts_cd, care_alt_src_rowid, CARE_LASTUP_DT, last_update, null_timestamp, null_number)
        -- NRML_ALT_ID Medicaid ID -> VALID_ALT_ID
        WHEN grp_medicaid_alt AND uq_medicaid_alt THEN
            INTO C_S_CRE_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
                  ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
                  TIMELINE_ACTION)
            VALUES (medicaid_alt_key, period_start, period_end, version_seq_num, rle_key, medicaid_tp_cd,
                    medicaid_alt_val, medicaid_tp_cd, sts_cd, medicaid_alt_src_rowid, CARE_LASTUP_DT, last_update,
                    null_timestamp, null_number)
        -- NRML_ALT_ID Medicaid ID -> RTR_VALID_ALT_ID.Default -> EXP_ALT_ID_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_ALT_ID
        WHEN grp_medicaid_exc AND uq_medicaid_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1)
            VALUES (mapping_name, run_ts, medicaid_tp_lbl, medicaid_tp_sys, medicaid_exception_code,
                    medicaid_exception_desc, medicaid_exception_type, medicaid_alt_id, mrg_care_id)
        -- NRML_ALT_ID SSN -> VALID_ALT_ID
        WHEN grp_ssn_alt AND uq_ssn_alt THEN
            INTO C_S_CRE_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
                  ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
                  TIMELINE_ACTION)
            VALUES (ssn_alt_key, period_start, period_end, version_seq_num, rle_key, ssn_tp_cd, ssn_out, ssn_tp_cd,
                    sts_cd, ssn_alt_src_rowid, CARE_LASTUP_DT, last_update, null_timestamp, null_number)
        -- NRML_ALT_ID SSN -> RTR_VALID_ALT_ID.Default -> EXP_ALT_ID_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_ALT_ID
        WHEN grp_ssn_exc AND uq_ssn_exc THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1)
            VALUES (mapping_name, run_ts, ssn_tp_lbl, ssn_tp_sys, ssn_exception_code, ssn_exception_desc,
                    ssn_exception_type, ssn_out, mrg_care_id)
    SELECT *
      FROM (
        WITH
        lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_any  AS (SELECT * FROM TABLE(fn_snow_helper42_common())),
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
        lkp_mc   AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_Stg_CRE_D_CARE_Clients (custom SQL; the parallel hint and commented test filters left out)
        src AS (
            SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
                   CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
                   CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN,
                   CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, CAST(NULL AS VARCHAR) AS SOURCE_ID,
                   CAST(NULL AS VARCHAR) AS TARGET_ID, CAST(NULL AS VARCHAR) AS REC, 'I' AS REC_TYPE
              FROM STG_CRE_D_CARE_CLIENTS CLIENTS
             WHERE CLIENTS.MAINT_FLAG IS NULL
            UNION ALL
            SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
                   CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
                   CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, DELTAS.MAINT_FLAG, CLIENTS.SSN,
                   CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
                   DECODE(MAINT.REC, 'CASEMOV', 'B', 'D')
              FROM STG_CRE_D_CARE_CLIENTS DELTAS
              LEFT JOIN STG_CRE_SN_CARE_CLIENTS CLIENTS
                ON DELTAS.CARE_ID = CLIENTS.CARE_ID
              JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
                ON CLIENTS.CARE_ID = MAINT.SOURCE_ID
               AND DELTAS.MAINT_FLAG = 'D'
               AND MAINT.REC IN ('CASEMOV', 'CASEDEL')
            UNION ALL
            SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
                   CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
                   CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN,
                   CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
                   'A' AS REC_TYPE
              FROM STG_CRE_SN_CARE_CLIENTS CLIENTS
              JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
                ON CLIENTS.CARE_ID = MAINT.TARGET_ID
               AND MAINT.REC = 'CASEMOV'
        ),
        -- LKP_XREF_SRC / LKP_XREF_TGT: CHAR columns are not compared blank-padded in Snowflake, hence the trims
        xref AS (
            SELECT x.PKEY_SRC_OBJECT, RTRIM(x.ROWID_OBJECT) AS ROWID_OBJECT,
                   RTRIM(x.ORIG_ROWID_OBJECT) AS ORIG_ROWID_OBJECT
              FROM C_B_PTY_XREF x
             WHERE TRIM(x.ROWID_SYSTEM) = 'CRE'
           QUALIFY ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.ROWID_XREF) = 1
        ),
        -- LKP_HMRG_SRC1 / LKP_HMRG_TGT1 (by SRC_ROWID_OBJECT) and LKP_HMRG_SRC2 / LKP_HMRG_TGT2 (by TGT_ROWID_OBJECT)
        hmrg_src AS (SELECT DISTINCT RTRIM(SRC_ROWID_OBJECT) AS ROWID_OBJECT FROM C_B_PTY_HMRG
                      WHERE SRC_ROWID_OBJECT IS NOT NULL),
        hmrg_tgt AS (SELECT DISTINCT RTRIM(TGT_ROWID_OBJECT) AS ROWID_OBJECT FROM C_B_PTY_HMRG
                      WHERE TGT_ROWID_OBJECT IS NOT NULL),
        -- RTR_MERGES (VALIDATION: NULL conditions route to the default group) + EXP_SRC_TGT_MRG_RSLT
        routed AS (
            SELECT s.*,
                   NVL(s.MAINT_FLAG IS NULL OR (s.MAINT_FLAG = 'D' AND s.REC = 'CASEDEL'), FALSE) AS grp_deletes,
                   xs.ROWID_OBJECT AS src_rowid_object,
                   xt.ROWID_OBJECT AS tgt_rowid_object,
                   (h1.ROWID_OBJECT IS NULL AND h2.ROWID_OBJECT IS NULL AND h3.ROWID_OBJECT IS NULL
                    AND h4.ROWID_OBJECT IS NULL) AS no_merge_history
              FROM src s
              LEFT JOIN xref xs ON xs.PKEY_SRC_OBJECT = s.SOURCE_ID
              LEFT JOIN xref xt ON xt.PKEY_SRC_OBJECT = s.TARGET_ID
              LEFT JOIN hmrg_src h1 ON h1.ROWID_OBJECT = xs.ORIG_ROWID_OBJECT
              LEFT JOIN hmrg_tgt h2 ON h2.ROWID_OBJECT = xs.ORIG_ROWID_OBJECT
              LEFT JOIN hmrg_src h3 ON h3.ROWID_OBJECT = xt.ORIG_ROWID_OBJECT
              LEFT JOIN hmrg_tgt h4 ON h4.ROWID_OBJECT = xt.ORIG_ROWID_OBJECT
        ),
        -- Union + mplt_Name_Standardization_Indv_Member (first, last, suffix and source system linked)
        named AS (
            SELECT r.*,
                   IFF(r.grp_deletes, NULL, IFF(r.no_merge_history, 'N', 'Y'))            AS orig_rowid_object_desc,
                   fn_snow_helper15_common(r.FIRSTNM, NULL, r.LASTNM, NULL, NULL, r.LAST_SUF, NULL,
                                           sf.MSTR_CODE_VALUE, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
              FROM routed r
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(r.FIRSTNM)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(r.LASTNM)) AND jl.IS_LAST_JUNK
              LEFT JOIN lkp_cv sf ON sf.CODE_TYPE = 'SUFFIX' AND sf.SRC_SYS = 'CRE' AND sf.SRC_CODE_VALUE = r.LAST_SUF
        ),
        -- rtr_Valid_Members, EXP_INVALID_MEMBERS, EXP_VALID_MEMBERS
        members AS (
            SELECT n.*,
                   n.nm:first_name::VARCHAR                                                AS std_first_name,
                   n.nm:last_name::VARCHAR                                                 AS std_lst_name,
                   n.nm:full_name::VARCHAR                                                 AS std_full_name,
                   n.nm:src_full_name::VARCHAR                                             AS std_src_full_name,
                   n.nm:sfx_name::VARCHAR                                                  AS std_sfx_name,
                   n.nm:src_suffix::VARCHAR                                                AS src_suffix,
                   n.nm:suffix_exception_code::VARCHAR                                     AS suffix_exception_code,
                   /* VALIDATION */
                   NVL(LENGTH(TRIM(n.nm:first_name::VARCHAR)) > 0 AND LENGTH(TRIM(n.nm:last_name::VARCHAR)) > 0,
                       FALSE)                                                              AS valid_member,
                   IFF(fn_snow_helper03_common(n.nm:first_name::VARCHAR), 'Missing_First_Name', NULL) AS fn_missing_code,
                   IFF(fn_snow_helper03_common(n.nm:last_name::VARCHAR), 'Missing_Last_Name', NULL)   AS ln_missing_code,
                   n.REC_TYPE IN ('B', 'D')                                                AS end_dated
              FROM named n
        ),
        -- SRT_VALID_MEMBERS + EXP_VALID_MEMBERS2 + LKP_INVALID_FIRSTNM / LASTNM + LKP_STATE_CODE
        ranked AS (
            SELECT m.*,
                   /* TIMELINE: VERSION_SEQ_NUM per CARE id, REC_TYPE descending */
                   IFF(m.valid_member,
                       ROW_NUMBER() OVER (PARTITION BY m.valid_member, m.CARE_ID ORDER BY m.REC_TYPE DESC), NULL)
                                                                                           AS version_seq_num,
                   xf.EXCEPTION_CODE AS fn_exception_code, xf.EXCEPTION_DESC AS fn_exception_desc,
                   xf.EXCEPTION_TYPE AS fn_exception_type,
                   xl.EXCEPTION_CODE AS ln_exception_code, xl.EXCEPTION_DESC AS ln_exception_desc,
                   xl.EXCEPTION_TYPE AS ln_exception_type,
                   IFF(m.orig_rowid_object_desc = 'N', m.TARGET_ID, m.CARE_ID)             AS mrg_care_id,
                   /* BAD DATA: SSN_OUT suppresses the default values */
                   IFF(m.SSN = 'U' OR m.SSN = 'N', NULL, m.SSN)                            AS ssn_out,
                   st.MSTR_CODE_VALUE                                                      AS std_state_cd
              FROM members m
              LEFT JOIN lkp_exc xf ON xf.EXCEPTION_CODE = m.fn_missing_code
              LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = m.ln_missing_code
              LEFT JOIN lkp_any st ON st.SRC_SYS = 'CRE' AND st.SRC_CODE_VALUE = m.STATE
        ),
        -- the mapplets and rules (only the de-duplicated members are routed to a target)
        dq AS (
            SELECT r.*,
                   NVL(r.version_seq_num = 1, FALSE)                                       AS is_member,
                   fn_snow_helper17_common(r.SEX, 'Indv', 'CRE')                           AS gd,
                   et.MSTR_CODE_VALUE                                                      AS ethnicity_mstr,
                   rc.MSTR_CODE_VALUE                                                      AS race_mstr,
                   fn_snow_helper23_common(r.PHONE)                                        AS phone_std,
                   fn_snow_helper37_common(r.mrg_care_id)                                  AS ci,
                   fn_snow_helper27_common(r.RECIP_NO)                                     AS md,
                   fn_snow_helper26_common(r.ssn_out)                                      AS sn,
                   /* RTR_US_ADDRESSES.US_ADDRESSES: STD_STATE_CD <> '99' OR ISNULL(STD_STATE_CD) */
                   NVL(r.std_state_cd <> '99', TRUE)                                       AS addr_us,
                   ss.MSTR_CODE_VALUE                                                      AS source_state_fips
              FROM ranked r
              LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'CRE' AND et.SRC_CODE_VALUE = r.FEDETH
              LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'CRE' AND rc.SRC_CODE_VALUE = r.RACE
              LEFT JOIN lkp_cv ss ON ss.CODE_TYPE = 'STATE' AND ss.SRC_SYS = 'CRE'
                                 AND ss.SRC_CODE_VALUE = UPPER(TRIM(r.STATE))
        ),
        -- mplt_Global_Addr_Validation (US addresses) + rule_Phone_Std exception code
        dq2 AS (
            SELECT d.*,
                   IFF(d.addr_us, fn_snow_helper34_common(d.STREET, NULL, d.CITY, d.STATE,
                                                          NVL(d.ZIP, '') || '-' || NVL(d.ZIPSUF, ''), 'US',
                                                          d.source_state_fips), NULL) AS av,
                   /* VALIDATION */
                   fn_snow_helper24_common(d.phone_std, NULL, NULL, ar.NPA_ID, ar.SERVICE)  AS phone_code
              FROM dq d
              LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.phone_std, 1, 3)
        ),
        -- lkp_ALT_ID_MSTR_REF_CODE: LOOKUP_CODE_VALUE of SRC_SYS CRE by source value (no code-type filter), any row
        alt_tp AS (
            SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE, l.MSTR_REF_LABEL, l.SRC_SYS
              FROM LOOKUP_CODE_VALUE l
             WHERE l.SRC_SYS = 'CRE' AND l.SRC_CODE_VALUE IN ('CARE ID', 'Medicaid ID', 'SSN')
           QUALIFY ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.CODE_TYPE) = 1
        ),
        flat AS (
            SELECT d.*,
                   d.CARE_ID                                                               AS pty_key,
                   NVL(d.CARE_ID, '') || '|' || :P_RLE_BO_CLASS_CD_MEMBER                  AS rle_key,
                   NVL(d.CARE_ID, '') || '|Member'                                         AS member_rle_fk,
                   /* TIMELINE: EXP_VALID_MEMBERS, EXP_PTY_HOLD / EXP_PTY_RLE_HOLD */
                   IFF(d.end_dated, DATEADD(day, -1, d.CARE_LASTUP_DT), d.CARE_LASTUP_DT)  AS period_start,
                   IFF(d.end_dated, d.CARE_LASTUP_DT, NULL)                                AS period_end,
                   IFF(d.end_dated, 2, NULL)                                               AS timeline_action,
                   IFF(d.end_dated, DATEADD(day, -1, d.CARE_LASTUP_DT), NULL)              AS period_reference_time,
                   IFF(d.end_dated, DATEADD(hour, -1, :l_run_ts), :l_run_ts)               AS last_update,
                   IFF(d.end_dated, DATEADD(day, 1, DATEADD(day, -1, d.CARE_LASTUP_DT)), NULL) AS pty_period_end,
                   IFF(d.end_dated, DATEADD(day, -1, d.CARE_LASTUP_DT), NULL)              AS pty_period_reference_time,
                   NVL(d.CARE_LASTUP_DT, d.INSERT_DATE)                                    AS src_last_update,
                   d.gd:mdm_gender_code::VARCHAR                                           AS mdm_gender_code,
                   d.gd:exception_code::VARCHAR                                            AS gender_exception_code,
                   xg.EXCEPTION_DESC                                                       AS gender_exception_description,
                   xg.EXCEPTION_TYPE                                                       AS gender_exception_type,
                   xs.EXCEPTION_DESC                                                       AS suffix_exception_desc,
                   xs.EXCEPTION_TYPE                                                       AS suffix_exception_type,
                   xe.EXCEPTION_CODE AS ethnicity_exception_code, xe.EXCEPTION_DESC AS ethnicity_exception_desc,
                   xe.EXCEPTION_TYPE AS ethnicity_exception_type,
                   xr.EXCEPTION_CODE AS race_exception_code, xr.EXCEPTION_DESC AS race_exception_desc,
                   xr.EXCEPTION_TYPE AS race_exception_type,
                   xp.EXCEPTION_CODE AS phone_exception_code, xp.EXCEPTION_DESC AS phone_exception_desc,
                   xp.EXCEPTION_TYPE AS phone_exception_type,
                   NVL(d.CARE_ID, '') || '|Member|Telephone|001|' || NVL(d.phone_std, '')  AS phn_key,
                   /* VALIDATION: RTR_VALID_ADDRESS / RTR_VALID_NON_US_ADDRESSES */
                   IFF(d.addr_us,
                       NVL((TRUNC(TRY_TO_NUMBER(d.av:mailability_score::VARCHAR)) >= 3
                            OR LEFT(d.av:match_code::VARCHAR, 1) NOT IN ('I', 'N'))
                           AND d.av:state_fips_cd::VARCHAR IS NOT NULL, FALSE),
                       d.CITY IS NOT NULL AND d.STREET IS NOT NULL)                       AS addr_valid,
                   IFF(d.addr_us, d.av:delivery_address_line1::VARCHAR, INITCAP(d.STREET)) AS a_line1,
                   IFF(d.addr_us, d.av:delivery_address_line2::VARCHAR, NULL)             AS a_line2,
                   IFF(d.addr_us, d.av:city::VARCHAR, INITCAP(d.CITY))                    AS a_city,
                   IFF(d.addr_us, d.av:state_fips_cd::VARCHAR, :P_DEFAULT_NONUS_STATE_CD) AS a_state,
                   IFF(d.addr_us, d.av:county_fips_cd::VARCHAR, d.CNTY)                   AS a_county_fips,
                   IFF(d.addr_us, d.av:country_iso2_char::VARCHAR, 'ZZ')                  AS a_country,
                   IFF(d.addr_us, d.av:zip_cd_5::VARCHAR, d.ZIP)                          AS a_postcode,
                   IFF(d.addr_us, d.av:zip_cd_4_extn::VARCHAR, d.ZIPSUF)                  AS a_postcode_ext,
                   d.av:geocoding_latitude::NUMBER(38, 6)                                  AS a_latitude,
                   d.av:geocoding_longitude::NUMBER(38, 6)                                 AS a_longitude,
                   d.av:mailability_score::VARCHAR                                         AS a_mailability_score,
                   d.av:match_code::VARCHAR                                                AS a_match_code,
                   d.av:address_type::VARCHAR                                              AS a_address_type,
                   d.av:sub_building_number::VARCHAR                                       AS a_sub_building_number,
                   d.av:sub_building_descriptor::VARCHAR                                   AS a_sub_building_descriptor,
                   d.av:sub_building_complete::VARCHAR                                     AS a_sub_building_complete,
                   d.av:building_number::VARCHAR                                           AS a_building_number,
                   d.av:building_name::VARCHAR                                             AS a_building_name,
                   d.av:residential_delivery_indicator::VARCHAR                            AS a_residential,
                   d.av:geocoding_status::VARCHAR                                          AS a_geocoding_status,
                   d.av:organization_name::VARCHAR                                         AS a_org_name,
                   d.av:organization_descriptor::VARCHAR                                   AS a_org_descriptor,
                   TRY_TO_NUMBER(d.av:mailability_score::VARCHAR)                          AS a_dr_mailability_score,
                   mc.DESCRIPTION                                                          AS a_dr_error_desc,
                   d.av:match_code::VARCHAR                                                AS a_dr_error_code,
                   NVL(d.STREET, '') || ' ' || '' || ' ' || NVL(d.CITY, '') || ' ' || NVL(d.STATE, '') || ' '
                   || NVL(d.ZIP, '')                                                       AS addr_attribute_value,
                   xa.EXCEPTION_CODE AS addr_exception_code, xa.EXCEPTION_DESC AS addr_exception_desc,
                   xa.EXCEPTION_TYPE AS addr_exception_type,
                   -- NRML_ALT_ID occurrences and lkp_ALT_ID_MSTR_REF_CODE
                   d.ci:id_value::VARCHAR                                                  AS care_alt_id,
                   t1.MSTR_REF_CODE                                                        AS care_tp_cd,
                   d.md:id_value::VARCHAR                                                  AS medicaid_alt_id,
                   d.md:exception_code::VARCHAR                                            AS medicaid_exception_code,
                   xm.EXCEPTION_DESC AS medicaid_exception_desc, xm.EXCEPTION_TYPE AS medicaid_exception_type,
                   t2.MSTR_REF_CODE AS medicaid_tp_cd, t2.MSTR_REF_LABEL AS medicaid_tp_lbl,
                   t2.SRC_SYS AS medicaid_tp_sys,
                   /* VALIDATION: exp_validate_ssn + Lkp_EXC_LOOKUP_CODE_VALUE_SSN (looked-up code) */
                   xn.EXCEPTION_CODE AS ssn_exception_code, xn.EXCEPTION_DESC AS ssn_exception_desc,
                   xn.EXCEPTION_TYPE AS ssn_exception_type,
                   t3.MSTR_REF_CODE AS ssn_tp_cd, t3.MSTR_REF_LABEL AS ssn_tp_lbl, t3.SRC_SYS AS ssn_tp_sys
              FROM dq2 d
              LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
              LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.suffix_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
              LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
              LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = d.phone_code
              LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = d.md:exception_code::VARCHAR
              LEFT JOIN lkp_exc xn ON xn.EXCEPTION_CODE = IFF(d.sn:ssn_status::VARCHAR = 'Invalid'
                                                              AND d.ssn_out IS NOT NULL, 'Invalid_SSN', NULL)
              LEFT JOIN lkp_exc xa ON xa.EXCEPTION_CODE = 'Invalid_Address'
              LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = d.av:match_code::VARCHAR
              LEFT JOIN alt_tp t1 ON t1.SRC_CODE_VALUE = 'CARE ID'
              LEFT JOIN alt_tp t2 ON t2.SRC_CODE_VALUE = 'Medicaid ID'
              LEFT JOIN alt_tp t3 ON t3.SRC_CODE_VALUE = 'SSN'
        ),
        keyed AS (
            SELECT f.*,
                   /* EXP_PTY_RLE_ADDR_HOLD.out_COUNTY_CD */
                   CASE WHEN f.a_state <> :P_DEFAULT_TX_STATE_CD THEN :P_COUNTY_CD_NONTX
                        WHEN f.a_county_fips IS NULL THEN :P_COUNTYCD_DEFAULTALL
                        ELSE f.a_county_fips END                                           AS a_county,
                   f.rle_key || '|' || :P_PHYSICAL_ADDR_TYPE_CD                            AS addr_key,
                   IFF(f.care_alt_id IN ('U', 'N'), NULL, f.care_alt_id)                   AS care_alt_val,
                   IFF(f.medicaid_alt_id IN ('U', 'N'), NULL, f.medicaid_alt_id)           AS medicaid_alt_val,
                   f.rle_key || '|' || NVL(f.care_tp_cd, '') || '|' || NVL(f.care_alt_id, '')         AS care_alt_key,
                   f.rle_key || '|' || NVL(f.medicaid_tp_cd, '') || '|' || NVL(f.medicaid_alt_id, '') AS medicaid_alt_key,
                   f.rle_key || '|' || NVL(f.ssn_tp_cd, '') || '|' || NVL(f.ssn_out, '')              AS ssn_alt_key,
                   /* routes (every flag NVL'd: a NULL router condition does not route) */
                   NOT f.grp_deletes AND NVL(f.orig_rowid_object_desc = 'N', FALSE)        AS grp_mrg,
                   NOT f.valid_member AND (f.fn_exception_code IS NOT NULL OR f.fn_exception_desc IS NOT NULL
                                           OR f.fn_exception_type IS NOT NULL)            AS grp_first_name,
                   NOT f.valid_member AND (f.ln_exception_code IS NOT NULL OR f.ln_exception_desc IS NOT NULL
                                           OR f.ln_exception_type IS NOT NULL)            AS grp_last_name,
                   f.is_member AND f.gender_exception_description IS NOT NULL              AS grp_gender,
                   f.is_member AND f.suffix_exception_code IS NOT NULL                     AS grp_suffix,
                   f.is_member AND f.ethnicity_exception_code IS NOT NULL                  AS grp_ethnicity,
                   f.is_member AND f.race_exception_code IS NOT NULL                       AS grp_race,
                   f.is_member AND f.addr_valid                                            AS grp_addr,
                   f.is_member AND NOT f.addr_valid                                        AS grp_addr_exc,
                   f.is_member AND f.PHONE IS NOT NULL AND f.phone_exception_code IS NULL  AS grp_phone,
                   f.is_member AND f.PHONE IS NOT NULL AND f.phone_exception_code IS NOT NULL AS grp_phone_exc,
                   f.is_member AND f.care_alt_id IS NOT NULL                               AS grp_care_alt,
                   f.is_member AND f.medicaid_alt_id IS NOT NULL AND f.medicaid_exception_code IS NULL
                                                                                           AS grp_medicaid_alt,
                   f.is_member AND f.medicaid_alt_id IS NOT NULL AND f.medicaid_exception_code IS NOT NULL
                                                                                           AS grp_medicaid_exc,
                   f.is_member AND f.ssn_out IS NOT NULL AND f.ssn_exception_code IS NULL  AS grp_ssn_alt,
                   f.is_member AND f.ssn_out IS NOT NULL AND f.ssn_exception_code IS NOT NULL AS grp_ssn_exc
              FROM flat f
        )
        SELECT k.*,
               'CRE'                                             AS src_sys,
               :l_run_ts                                         AS run_ts,
               :c_mapping                                        AS mapping_name,
               'Indv'                                            AS pty_bo_class_cd,
               :P_RLE_BO_CLASS_CD_MEMBER                         AS rle_bo_class_cd,
               :P_PHYSICAL_ADDR_TYPE_CD                          AS addr_tp,
               'Payer'                                           AS hierarchy_code,
               'Primary'                                         AS pref_lvl,
               'Member Addr'                                     AS hm_rel_tp_cd,
               'US'                                              AS src_cntry,
               'Telephone'                                       AS phn_tp,
               '001'                                             AS usg_tp_phone,
               'Issued'                                          AS sts_cd,
               'First Name'                                      AS attr_first_name,
               'Last Name'                                       AS attr_last_name,
               'Gender'                                          AS attr_gender,
               'Name Suffix'                                     AS attr_suffix,
               'FEDETH'                                          AS attr_fedeth,
               'RACE'                                            AS attr_race,
               'Address'                                         AS attr_address,
               'Telephone'                                       AS attr_phone,
               CAST(NULL AS TIMESTAMP_NTZ)                       AS null_timestamp,   -- TIMELINE: not linked
               CAST(NULL AS NUMBER)                              AS null_number,      -- TIMELINE: not linked
               /* BAD DATA: SRC_ROWID is 30 characters */
               LEFT(k.addr_key, 30)                              AS addr_src_rowid,
               LEFT(k.phn_key, 30)                               AS phn_src_rowid,
               LEFT(k.care_alt_key, 30)                          AS care_alt_src_rowid,
               LEFT(k.medicaid_alt_key, 30)                      AS medicaid_alt_src_rowid,
               LEFT(k.ssn_alt_key, 30)                           AS ssn_alt_src_rowid,
               /* BAD DATA: unique keys Snowflake does not enforce */
               ROW_NUMBER() OVER (PARTITION BY k.grp_first_name, k.CARE_ID, k.fn_exception_type, k.fn_exception_code
                                  ORDER BY k.REC_TYPE DESC) = 1  AS uq_first_name,
               ROW_NUMBER() OVER (PARTITION BY k.grp_last_name, k.CARE_ID, k.ln_exception_type, k.ln_exception_code
                                  ORDER BY k.REC_TYPE DESC) = 1  AS uq_last_name,
               xpty.PKEY_SRC_OBJECT IS NULL                      AS uq_pty,
               xrle.PKEY_SRC_OBJECT IS NULL                      AS uq_rle,
               xadr.PKEY_SRC_OBJECT IS NULL                      AS uq_addr,
               xphn.PKEY_SRC_OBJECT IS NULL                      AS uq_phone,
               xca.PKEY_SRC_OBJECT IS NULL                       AS uq_care_alt,
               xma.PKEY_SRC_OBJECT IS NULL                       AS uq_medicaid_alt,
               xsa.PKEY_SRC_OBJECT IS NULL                       AS uq_ssn_alt,
               ROW_NUMBER() OVER (PARTITION BY k.grp_medicaid_exc, k.mrg_care_id, k.medicaid_exception_type,
                                               k.medicaid_exception_code ORDER BY k.REC_TYPE DESC) = 1
                                                                 AS uq_medicaid_exc,
               ROW_NUMBER() OVER (PARTITION BY k.grp_ssn_exc, k.mrg_care_id, k.ssn_exception_type,
                                               k.ssn_exception_code ORDER BY k.REC_TYPE DESC) = 1
                                                                 AS uq_ssn_exc
          FROM keyed k
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY WHERE VERSION_SEQ = 1) xpty
                 ON xpty.PKEY_SRC_OBJECT = k.pty_key
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE WHERE VERSION_SEQ = 1) xrle
                 ON xrle.PKEY_SRC_OBJECT = k.rle_key
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xadr
                 ON xadr.PKEY_SRC_OBJECT = k.addr_key
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xphn
                 ON xphn.PKEY_SRC_OBJECT = k.phn_key
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xca
                 ON xca.PKEY_SRC_OBJECT = k.care_alt_key
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xma
                 ON xma.PKEY_SRC_OBJECT = k.medicaid_alt_key
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xsa
                 ON xsa.PKEY_SRC_OBJECT = k.ssn_alt_key
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, '
                                   || 'C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN, C_S_CRE_PTY_RLE_ALT_ID, exceptions)',
                                   :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
