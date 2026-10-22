--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_CRE_CARE_Clients (workflow wf_CRE_Stage_Load_Ongoing, its only
-- mapping; the workflow task is called m_TGT_C_S_CRE_CARE_CLIENTS).
--
-- CARE clients (custom SQL on STG_CRE_D_CARE_CLIENTS: new and changed clients REC_TYPE 'I'; deleted cases 'D' and
-- moved cases 'B' from the snapshot STG_CRE_SN_CARE_CLIENTS through STG_CRE_D_CARE_CASE_MAINT; the targets of the
-- moves 'A'):
--   -> RTR_MERGES (a row goes to every matching group):
--        DELETES (MAINT_FLAG NULL, or 'D' with REC 'CASEDEL') -> EXP_REGULAR_DELETES (ORIG_ROWID_OBJECT_DESC NULL)
--        Default -> LKP_XREF_SRC / LKP_XREF_TGT (C_B_PTY_XREF of CRE, by SOURCE_ID / TARGET_ID)
--                -> LKP_HMRG_SRC1/2, LKP_HMRG_TGT1/2 (C_B_PTY_HMRG by the original records)
--                -> ORIG_ROWID_OBJECT_DESC 'N' (no merge history at all) or 'Y'
--                -> FLTR_CRE_MRG ('N') -> CRE_SRC_MRG (source and target ROWID_OBJECT, run date)
--   -> Union -> mplt_Name_Standardization_Indv_Member (first name, last name, suffix; no middle or full name)
--   -> rtr_Valid_Members:
--        Default (standardized first or last name blank) -> Missing_First_Name / Missing_Last_Name looked up in
--          EXC_LOOKUP_CODE_VALUE -> rtr_Invalid_First_Last_Name -> EXC_STG_BAD_REC_MEMB (first, last or both)
--        VALID_MEMBERS -> SRT_VALID_MEMBERS (CARE id, REC_TYPE descending) -> VERSION_SEQ_NUM per CARE id
--          -> Filt_DeDeup_Seq1 / FLTR_NULL_ALT_ID_SEQ1 (VERSION_SEQ_NUM = 1: one row per CARE id, I > D > B > A)
--             -> EXP_PTY -> gender, ethnicity, race -> C_S_CRE_PTY; EXP_PTY_RLE_HOLD -> C_S_CRE_PTY_RLE
--                gender, suffix, ethnicity and race exceptions -> EXC_STG_BAD_REC_MEMB
--             -> EXP_ADDRESSES -> LKP_STATE_CODE -> RTR_US_ADDRESSES:
--                  US (state not '99') -> mplt_Global_Addr_Validation -> RTR_VALID_ADDRESS
--                  non-US -> INITCAP street and city, state '99', country 'ZZ' -> RTR_VALID_NON_US_ADDRESSES
--                  -> good: C_S_CRE_PTY_RLE_ADDR (one per member, type 002); bad: EXC_STG_BAD_REC_MEMB
--             -> FLTR_NULL_PHONE -> rule_Phone_Std -> RTR_VALID_PHONE -> C_S_CRE_PTY_RLE_PHN or EXC_STG_BAD_REC_MEMB
--             -> NRML_ALT_ID: CARE ID (rule_CARE_ID_Std of MRG_CARE_ID), Medicaid ID (rule_MEDICAID_ID_Std of
--                RECIP_NO), SSN -> lkp_ALT_ID_MSTR_REF_CODE -> RTR_VALID_ALT_ID -> C_S_CRE_PTY_RLE_ALT_ID or
--                EXC_STG_BAD_REC_MEMB
-- Every target is insert only, never truncated.
--
-- VALIDATION: name (fn_dq_std_name_indv_member; a member needs a standardized first AND last name), gender
--   (fn_dq_valid_gender), ethnicity and race (fn_dq_valid_ethnicity / fn_dq_valid_race), suffix (from the name
--   mapplet), address (RTR_VALID_ADDRESS: (TO_INTEGER(mailability score) >= 3 OR match code not starting I / N) AND
--   a state FIPS; non-US: city and street present), phone (fn_dq_std_phone with only the number linked, so the
--   CRE toll-free check never runs), Medicaid id (fn_dq_std_medicaid_id), SSN (fn_dq_valid_ssn). No birth-date rule.
--   The name, phone, SSN and address routes test the code AS LOOKED UP in EXC_LOOKUP_CODE_VALUE: an unconfigured
--   code means no name exception row, a loaded phone, a loaded SSN, and an address exception row with a NULL code.
--   Gender, ethnicity and race exception rows are written only when configured; the suffix and Medicaid rows write
--   the computed code.
-- BAD DATA: invalid members are logged and dropped; a bad address, phone or alternate id is logged instead of loaded
--   (the member itself is loaded); SSN 'U' / 'N' is blanked and dropped; CARE and Medicaid ids lose their special
--   characters; SRC_ROWID is cut to its 30 characters (IDQ truncates to the target precision); with no AddressDoctor
--   score and no match code the RTR_VALID_ADDRESS condition is NULL, so such a US address is an exception.
-- TIMELINE: VERSION_SEQ = VERSION_SEQ_NUM (1 for every written row). 'B' (moved away) and 'D' (deleted) rows are
--   end-dated: PERIOD_START_DATE = CARE_LASTUP_DT - 1 day, PERIOD_END_DATE = CARE_LASTUP_DT, TIMELINE_ACTION = 2,
--   PERIOD_REFERENCE_TIME = PERIOD_START_DATE, LAST_UPDATE_DATE = run start - 1 hour (the role keeps the run start).
--   'I' and 'A' rows: PERIOD_START_DATE = CARE_LASTUP_DT, the rest NULL. The role and the alternate ids do not link
--   TIMELINE_ACTION / PERIOD_REFERENCE_TIME (NULL).
--
-- IDQ quirks kept:
--   * A case move is written to CRE_SRC_MRG when NEITHER record has merge history - also when the CARE ids have no
--     cross-reference at all (both ROWID_OBJECTs NULL) - and once more for the move target row ('A') when the
--     snapshot gives it a MAINT_FLAG.
--   * The CARE ID alternate id of an unmerged move ('N') is the TARGET id (MRG_CARE_ID), under the key of the
--     source member; its exception rows carry the merged id as SRC_SYS_ID_1.
--   * LKP_STATE_CODE has no code-type filter and "return last row"; fn_ors_helper03_common returns any row.
--   * lkp_ALT_ID_MSTR_REF_CODE has no code-type filter either; when the type does not translate, ALT_ID_TP is NULL
--     and the exception row has SRC_SYS NULL.
--   * The address exception row takes code, description and type from Lkp_EXC_LOOKUP_CODE_VALUE; the hard-coded
--     ones of EXP_ADDRESS_EXC_METADATA / EXP_NON_US_ADDRESSES (type and description swapped) are not written.
--   * PKEY_SRC_OBJECT_ADDR (validated address text) is computed in IDQ but not linked.
--   * Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND everywhere, LOC_IDN,
--     MDL_NM, PRFX_NM, SRC_ADDR_LN_2, ADDR_LN_2 of non-US addresses, CREATE_DATE of the alternate ids.
--
-- Open risk (README, UQ_EXC_STG_BAD_REC_MEMB): a CARE id read twice with a missing name (delta and move target), or
-- the source and target of an unmerged move logging the same Medicaid / SSN exception under the target id, gives two
-- equal exception rows. IDQ rejects the second and carries on; this statement fails as a whole.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients (
    p_physical_addr_type_cd   IN VARCHAR2 DEFAULT '002',      -- $PHYSICAL_ADDR_TYPE_CD
    p_rle_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Member',   -- $RLE_BO_CLASS_CD_Member
    p_default_tx_state_cd     IN VARCHAR2 DEFAULT '48',       -- $Default_TX_State_CD
    p_county_cd_nontx         IN VARCHAR2 DEFAULT '996',      -- $County_CD_NonTX
    p_countycd_defaultall     IN VARCHAR2 DEFAULT '998',      -- $CountyCD_DefaultAll
    p_default_nonus_state_cd  IN VARCHAR2 DEFAULT '99'        -- $Default_NonUS_State_CD
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_CRE_CARE_Clients';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SESSSTARTTIME / SYSTIMESTAMP()
BEGIN
    -- Not performed: IDQ "truncate target table" of CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN, C_S_CRE_PTY_RLE_ALT_ID. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        ------------------------------------------------------------------------------------------------------------
        -- RTR_MERGES.Default -> FLTR_CRE_MRG -> Write_CRE_SRC_MRG
        ------------------------------------------------------------------------------------------------------------
        WHEN grp_deletes = 0 AND orig_rowid_object_desc = 'N' THEN
            INTO CRE_SRC_MRG (SRC_ROWID_OBJECT, TGT_ROWID_OBJECT, RUN_DATE)
            VALUES (src_rowid_object, tgt_rowid_object, l_run_ts)
        ------------------------------------------------------------------------------------------------------------
        -- rtr_Valid_Members.Default -> rtr_Invalid_First_Last_Name (VALIDATION, looked-up codes)
        ------------------------------------------------------------------------------------------------------------
        -- FirstName_Issue -> Write_EXC_STG_BAD_REC_MEMB_FName
        WHEN valid_member = 0
             AND (fn_exception_code IS NOT NULL OR fn_exception_desc IS NOT NULL OR fn_exception_type IS NOT NULL) THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_1, RUN_DATE, MAPPING_NAME, FIRST_NAME, LAST_NAME, ATTRIBUTE_NAME, GENDER, BIRTH_DATE,
                  SUFFIX, SRC_SYS, ATTRIBUTE_VALUE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
            VALUES (CARE_ID, l_run_ts, c_mapping, std_first_name, std_lst_name, 'First Name', SEX, BIRTH_DT,
                    std_sfx_name, 'CRE', FIRSTNM, fn_exception_type, fn_exception_desc, fn_exception_code)
        -- LastName_Issue -> exp_Last_Name_Exception -> Write_EXC_STG_BAD_REC_MEMB_LName
        WHEN valid_member = 0
             AND (ln_exception_code IS NOT NULL OR ln_exception_desc IS NOT NULL OR ln_exception_type IS NOT NULL) THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, FIRST_NAME, MAPPING_NAME, BIRTH_DATE, GENDER, ADDRESS_LINE_1,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ATTRIBUTE_NAME, LAST_NAME,
                  SUFFIX, ATTRIBUTE_VALUE, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES ('CRE', CARE_ID, l_run_ts, std_first_name, c_mapping, BIRTH_DT, SEX, STREET, CITY, CNTY, STATE,
                    ZIP, ZIPSUF, 'Last Name', std_lst_name, std_sfx_name, LASTNM, ln_exception_code,
                    ln_exception_desc, ln_exception_type)
        ------------------------------------------------------------------------------------------------------------
        -- VALID_MEMBERS -> Filt_DeDeup_Seq1 (TIMELINE: VERSION_SEQ_NUM = 1)
        ------------------------------------------------------------------------------------------------------------
        -- EXP_PTY -> EXP_PTY_HOLD -> SRT_MRG_RECORDS -> Write_C_S_CRE_PTY
        WHEN version_seq_num = 1 THEN
            INTO C_S_CRE_PTY
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY,
                  CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND, BIRTH_DT, FULL_NM, GNDR_CD, SFX_NM, LST_NM, MDL_NM,
                  PRFX_NM, FRST_NM, PTY_BO_CLASS_CD, SRC_FULL_NM, SRC_LAST_UPD_DT, ETHNCTY, RACE_CD, SRC_ETHNCTY,
                  SRC_RACE_CD)
            VALUES (pty_key, NULL, NULL, NULL, NULL, period_start /* TIMELINE */, pty_period_end /* TIMELINE */,
                    version_seq_num /* TIMELINE */, pty_period_reference_time /* TIMELINE */,
                    timeline_action /* TIMELINE */, last_update, NULL, last_update, NULL, pty_key, NULL, BIRTH_DT,
                    std_full_name, mdm_gender_code, std_sfx_name, std_lst_name, NULL, NULL, std_first_name, 'Indv',
                    std_src_full_name, src_last_update, ethnicity_mstr, race_mstr, FEDETH, RACE)
        -- EXP_PTY_RLE_HOLD -> Write_C_S_CRE_PTY_RLE (LAST_UPDATE_DATE is the run start for every row)
        WHEN version_seq_num = 1 THEN
            INTO C_S_CRE_PTY_RLE
                 (PTY_FK, PKEY_SRC_OBJECT, SRC_ROWID, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
                  PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, RLE_BO_CLASS_CD, CREATE_DATE,
                  UPDATED_BY, CREATOR, HUB_STATE_IND, SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME, TIMELINE_ACTION)
            VALUES (pty_key, rle_key, rle_key, NULL, NULL, NULL, NULL, period_start /* TIMELINE */,
                    pty_period_end /* TIMELINE */, version_seq_num /* TIMELINE */, l_run_ts, p_rle_bo_class_cd_member,
                    l_run_ts, NULL, NULL, NULL, src_last_update, NULL /* TIMELINE: not linked */,
                    NULL /* TIMELINE: not linked */)
        -- fltr_Gender_Exc -> Exp_Write_Gender_Exc -> Write_EXC_STG_BAD_REC_MEMB_Gender_Cd (VALIDATION)
        WHEN version_seq_num = 1 AND gender_exception_description IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
                  EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC)
            VALUES ('CRE', CARE_ID, l_run_ts, SEX, 'Gender', SEX, c_mapping, gender_exception_type,
                    gender_exception_code, gender_exception_description)
        -- fltr_Suffix_exc -> Exp_Write_Suffix_Exc -> Write_EXC_STG_BAD_REC_MEMB_Suffix (computed code)
        WHEN version_seq_num = 1 AND suffix_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, MAPPING_NAME)
            VALUES ('CRE', CARE_ID, fn_ors_helper05_common(suffix_exception_code), suffix_exception_code,
                    fn_ors_helper04_common(suffix_exception_code), l_run_ts, 'Name Suffix', src_suffix, c_mapping)
        -- Filt_Bad_Ethnicity_Cd -> Write_EXC_STG_BAD_REC_MEMB_Ethnicity_Cd (VALIDATION, looked-up code)
        WHEN version_seq_num = 1 AND ethnicity_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, EXCEPTION_CODE,
                  EXCEPTION_TYPE, EXCEPTION_DESC)
            VALUES ('CRE', pty_key, l_run_ts, 'FEDETH', FEDETH, c_mapping, ethnicity_exception_code,
                    ethnicity_exception_type, ethnicity_exception_desc)
        -- Filt_Bad_Race_Cd -> Write_EXC_STG_BAD_REC_MEMB_Race_Cd (VALIDATION, looked-up code)
        WHEN version_seq_num = 1 AND race_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, EXCEPTION_TYPE,
                  EXCEPTION_DESC, EXCEPTION_CODE)
            VALUES ('CRE', pty_key, l_run_ts, 'RACE', RACE, c_mapping, race_exception_type, race_exception_desc,
                    race_exception_code)
        -- RTR_VALID_ADDRESS.VALID_ADDRESSES / RTR_VALID_NON_US_ADDRESSES.VALID_NON_US_ADDRESSES -> UNION_ADDRESSES
        -- -> EXP_PTY_RLE_ADDR_HOLD -> Write_C_S_CRE_PTY_RLE_ADDR
        WHEN version_seq_num = 1 AND addr_valid = 1 THEN
            INTO C_S_CRE_PTY_RLE_ADDR
                 (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, LAST_UPDATE_DATE, ROWID_OBJECT, DELETED_IND, DELETED_DATE,
                  DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, CREATE_DATE,
                  CREATOR, UPDATED_BY, HUB_STATE_IND, LOC_IDN, HIERARCHY_CODE, PREF_LVL, ADDR_TP, HM_REL_TP_CD,
                  ADDR_LN_1, ADDR_LN_2, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD, LNGTD, MLBLTY_SCR,
                  PTY_RLE_FK, USG_TP, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY,
                  SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, FLR_NUM, ADDR_TP_CD, SUB_BLDG_DESC, SUB_BLDG_NM,
                  BLDG_NMBR, BLDNG_NM, RSDNTL_DLVRY_IND, GEOCD_STS_CD, ORG_NM, ORG_DESC, VLDTN_MSG)
            VALUES (addr_key, SUBSTR(addr_key, 1, 30) /* BAD DATA */, version_seq_num /* TIMELINE */, last_update,
                    NULL, NULL, NULL, NULL, period_start /* TIMELINE */, period_end /* TIMELINE */,
                    period_reference_time /* TIMELINE */, timeline_action /* TIMELINE */, last_update, NULL, NULL,
                    NULL, NULL, 'Payer', 'Primary', p_physical_addr_type_cd, 'Member Addr', a_line1, a_line2, a_city,
                    a_county, a_state, a_country, a_postcode, a_postcode_ext, a_latitude, a_longitude,
                    a_mailability_score, rle_key, p_physical_addr_type_cd, STREET, NULL, CITY, CNTY, STATE, 'US', ZIP,
                    ZIPSUF, CARE_LASTUP_DT, a_sub_building_number, a_address_type, a_sub_building_descriptor,
                    a_sub_building_complete, a_building_number, a_building_name, a_residential, a_geocoding_status,
                    a_org_name, a_org_descriptor, a_match_code)
        -- RTR_VALID_ADDRESS.Default / RTR_VALID_NON_US_ADDRESSES.Default -> UNION_INVALID_ADDRESSES
        -- -> Lkp_EXC_LOOKUP_CODE_VALUE -> Write_EXC_STG_BAD_REC_MEMB_ADDR (BAD DATA, looked-up Invalid_Address)
        WHEN version_seq_num = 1 AND addr_valid = 0 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, RUN_DATE, MAPPING_NAME, ADDRESS_DR_MAILABILITY_SCORE, ADDRESS_DR_ERROR_DESC,
                  ADDRESS_DR_ERROR_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1, ADDRESS_LINE_1, ADDRESS_LINE_2,
                  ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
                  EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE)
            VALUES ('CRE', l_run_ts, c_mapping, a_dr_mailability_score, a_dr_error_desc, a_dr_error_code, 'Address',
                    STREET || ' ' || NULL || ' ' || CITY || ' ' || STATE || ' ' || ZIP, CARE_ID, STREET, NULL, CITY,
                    CNTY, STATE, ZIP, ZIPSUF, 'US', fn_ors_helper08_common('Invalid_Address'),
                    fn_ors_helper04_common('Invalid_Address'), fn_ors_helper05_common('Invalid_Address'))
        -- FLTR_NULL_PHONE -> rule_Phone_Std -> RTR_VALID_PHONE.VALID -> EXP_PTY_RLE_PHN_HOLD -> Write_C_S_CRE_PTY_RLE_PHN
        WHEN version_seq_num = 1 AND PHONE IS NOT NULL AND phone_exception_code IS NULL THEN
            INTO C_S_CRE_PTY_RLE_PHN
                 (PKEY_SRC_OBJECT, SRC_ROWID, PHN_NUM, VERSION_SEQ, LAST_UPDATE_DATE, PHN_TP, PTY_RLE_FK, USG_TP,
                  PREF_LVL, PERIOD_START_DATE, PERIOD_END_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, ROWID_OBJECT,
                  DELETED_IND, DELETED_DATE, DELETED_BY, CREATE_DATE, UPDATED_BY, CREATOR, HUB_STATE_IND,
                  SRC_LAST_UPD_DT)
            VALUES (phn_key, SUBSTR(phn_key, 1, 30) /* BAD DATA */, phone_std, version_seq_num /* TIMELINE */,
                    last_update, 'Telephone', pty_key || '|Member', '001', 'Primary', period_start /* TIMELINE */,
                    period_end /* TIMELINE */, timeline_action /* TIMELINE */, period_reference_time /* TIMELINE */,
                    NULL, NULL, NULL, NULL, last_update, NULL, NULL, NULL, CARE_LASTUP_DT)
        -- RTR_VALID_PHONE.Default -> EXP_PTY_RLE_PHN_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_PHONE (VALIDATION)
        WHEN version_seq_num = 1 AND PHONE IS NOT NULL AND phone_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, PRIMARY_PHONE, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1,
                  EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC)
            VALUES ('CRE', phone_std, c_mapping, l_run_ts, 'Telephone', phone_std, CARE_ID, phone_exception_code,
                    phone_exception_type, phone_exception_desc)
        ------------------------------------------------------------------------------------------------------------
        -- NRML_ALT_ID (three occurrences) -> lkp_ALT_ID_MSTR_REF_CODE -> FLTR_NULL_ALT_ID_SEQ1 (value present,
        -- TIMELINE: VERSION_SEQ_NUM = 1) -> RTR_VALID_ALT_ID
        ------------------------------------------------------------------------------------------------------------
        -- CARE ID: rule_CARE_ID_Std returns no exception, so always VALID_ALT_ID
        WHEN version_seq_num = 1 AND care_alt_id IS NOT NULL THEN
            INTO C_S_CRE_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, UPDATED_BY, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD,
                  CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION)
            VALUES (care_alt_key, NULL, NULL, NULL, NULL, period_start /* TIMELINE */, period_end /* TIMELINE */,
                    version_seq_num /* TIMELINE */, NULL, rle_key, care_tp_cd,
                    CASE WHEN care_alt_id IN ('U', 'N') THEN NULL ELSE care_alt_id END, care_tp_cd, 'Issued', NULL,
                    NULL, NULL, SUBSTR(care_alt_key, 1, 30) /* BAD DATA */, CARE_LASTUP_DT, last_update,
                    NULL /* TIMELINE: not linked */, NULL /* TIMELINE: not linked */)
        -- Medicaid ID: VALID_ALT_ID
        WHEN version_seq_num = 1 AND medicaid_alt_id IS NOT NULL AND medicaid_exception_code IS NULL THEN
            INTO C_S_CRE_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, UPDATED_BY, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD,
                  CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION)
            VALUES (medicaid_alt_key, NULL, NULL, NULL, NULL, period_start /* TIMELINE */,
                    period_end /* TIMELINE */, version_seq_num /* TIMELINE */, NULL, rle_key, medicaid_tp_cd,
                    CASE WHEN medicaid_alt_id IN ('U', 'N') THEN NULL ELSE medicaid_alt_id END, medicaid_tp_cd,
                    'Issued', NULL, NULL, NULL, SUBSTR(medicaid_alt_key, 1, 30) /* BAD DATA */, CARE_LASTUP_DT,
                    last_update, NULL /* TIMELINE: not linked */, NULL /* TIMELINE: not linked */)
        -- Medicaid ID: Default -> EXP_ALT_ID_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_ALT_ID (computed code)
        WHEN version_seq_num = 1 AND medicaid_alt_id IS NOT NULL AND medicaid_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1)
            VALUES (c_mapping, l_run_ts, medicaid_tp_lbl, medicaid_tp_sys, medicaid_exception_code,
                    medicaid_exception_desc, medicaid_exception_type, medicaid_alt_id, mrg_care_id)
        -- SSN: VALID_ALT_ID (an invalid SSN whose exception is not configured is loaded)
        WHEN version_seq_num = 1 AND ssn_out IS NOT NULL AND ssn_exception_code IS NULL THEN
            INTO C_S_CRE_PTY_RLE_ALT_ID
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
                  PERIOD_END_DATE, VERSION_SEQ, UPDATED_BY, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD,
                  CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION)
            VALUES (ssn_alt_key, NULL, NULL, NULL, NULL, period_start /* TIMELINE */, period_end /* TIMELINE */,
                    version_seq_num /* TIMELINE */, NULL, rle_key, ssn_tp_cd, ssn_out, ssn_tp_cd, 'Issued', NULL,
                    NULL, NULL, SUBSTR(ssn_alt_key, 1, 30) /* BAD DATA */, CARE_LASTUP_DT, last_update,
                    NULL /* TIMELINE: not linked */, NULL /* TIMELINE: not linked */)
        -- SSN: Default -> EXP_ALT_ID_EXC_HOLD -> Write_EXC_STG_BAD_REC_MEMB_ALT_ID (looked-up Invalid_SSN)
        WHEN version_seq_num = 1 AND ssn_out IS NOT NULL AND ssn_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1)
            VALUES (c_mapping, l_run_ts, ssn_tp_lbl, ssn_tp_sys, ssn_exception_code, ssn_exception_desc,
                    ssn_exception_type, ssn_out, mrg_care_id)
    WITH
    -- Read_Stg_CRE_D_CARE_Clients (custom SQL, query mode SEMI; the parallel hint and the commented test filters
    -- are left out) + exp_Hold_Src_Rec
    src AS (
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE, CLIENTS.ZIP,
               CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN, CLIENTS.INSERT_DATE,
               CLIENTS.FEDETH, CLIENTS.RACE, CAST(NULL AS VARCHAR2(10)) AS SOURCE_ID,
               CAST(NULL AS VARCHAR2(10)) AS TARGET_ID, CAST(NULL AS VARCHAR2(13)) AS REC, 'I' AS REC_TYPE
          FROM STG_CRE_D_CARE_CLIENTS CLIENTS
         WHERE CLIENTS.MAINT_FLAG IS NULL
        UNION ALL
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE, CLIENTS.ZIP,
               CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, DELTAS.MAINT_FLAG, CLIENTS.SSN, CLIENTS.INSERT_DATE,
               CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
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
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE, CLIENTS.ZIP,
               CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN, CLIENTS.INSERT_DATE,
               CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC, 'A' AS REC_TYPE
          FROM STG_CRE_SN_CARE_CLIENTS CLIENTS
          JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
            ON CLIENTS.CARE_ID = MAINT.TARGET_ID
           AND MAINT.REC = 'CASEMOV'
    ),
    -- LKP_XREF_SRC / LKP_XREF_TGT: C_B_PTY_XREF of ROWID_SYSTEM CRE (CHAR(14), blank-padded comparison), any row
    xref AS (
        SELECT x.PKEY_SRC_OBJECT, x.ROWID_OBJECT, x.ORIG_ROWID_OBJECT,
               ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.ROWID_XREF) AS rn
          FROM C_B_PTY_XREF x
         WHERE x.ROWID_SYSTEM = 'CRE'
    ),
    -- RTR_MERGES + EXP_REGULAR_DELETES / EXP_SRC_TGT_MRG_RSLT (+ LKP_HMRG_*) + EXP_MRG_RSLT + Union
    union_rows AS (
        SELECT s.*,
               CASE WHEN s.MAINT_FLAG IS NULL OR (s.MAINT_FLAG = 'D' AND s.REC = 'CASEDEL') THEN 1 ELSE 0 END
                                                                                        AS grp_deletes,
               xs.ROWID_OBJECT                                                          AS src_rowid_object,
               xt.ROWID_OBJECT                                                          AS tgt_rowid_object,
               CASE WHEN s.MAINT_FLAG IS NULL OR (s.MAINT_FLAG = 'D' AND s.REC = 'CASEDEL') THEN NULL
                    WHEN EXISTS (SELECT 1 FROM C_B_PTY_HMRG h WHERE h.SRC_ROWID_OBJECT = xs.ORIG_ROWID_OBJECT)
                      OR EXISTS (SELECT 1 FROM C_B_PTY_HMRG h WHERE h.TGT_ROWID_OBJECT = xs.ORIG_ROWID_OBJECT)
                      OR EXISTS (SELECT 1 FROM C_B_PTY_HMRG h WHERE h.SRC_ROWID_OBJECT = xt.ORIG_ROWID_OBJECT)
                      OR EXISTS (SELECT 1 FROM C_B_PTY_HMRG h WHERE h.TGT_ROWID_OBJECT = xt.ORIG_ROWID_OBJECT)
                    THEN 'Y' ELSE 'N' END                                               AS orig_rowid_object_desc
          FROM src s
          LEFT JOIN xref xs ON xs.PKEY_SRC_OBJECT = s.SOURCE_ID AND xs.rn = 1
          LEFT JOIN xref xt ON xt.PKEY_SRC_OBJECT = s.TARGET_ID AND xt.rn = 1
    ),
    -- mplt_Name_Standardization_Indv_Member (first, last, suffix and source system linked)
    named AS (
        SELECT /*+ NO_MERGE */
               u.*,
               fn_dq_std_name_indv_member(u.FIRSTNM, NULL, u.LASTNM, NULL, NULL, u.LAST_SUF, NULL, NULL, 'CRE') AS nm
          FROM union_rows u
    ),
    -- rtr_Valid_Members + EXP_INVALID_MEMBERS + LKP_INVALID_FIRSTNM / LASTNM; EXP_VALID_MEMBERS + SRT_VALID_MEMBERS
    -- + EXP_VALID_MEMBERS2
    members AS (
        SELECT n.*,
               n.nm.first_name                                                          AS std_first_name,
               n.nm.lst_name                                                            AS std_lst_name,
               n.nm.full_name                                                           AS std_full_name,
               n.nm.src_full_name                                                       AS std_src_full_name,
               n.nm.sfx_name                                                            AS std_sfx_name,
               n.nm.src_suffix                                                          AS src_suffix,
               n.nm.suffix_exception_code                                               AS suffix_exception_code,
               /* VALIDATION */
               CASE WHEN LENGTH(TRIM(n.nm.first_name)) > 0 AND LENGTH(TRIM(n.nm.lst_name)) > 0 THEN 1 ELSE 0 END
                                                                                        AS valid_member,
               CASE WHEN TRIM(n.nm.first_name) IS NULL THEN 'Missing_First_Name' END    AS fn_missing_code,
               CASE WHEN TRIM(n.nm.lst_name) IS NULL THEN 'Missing_Last_Name' END       AS ln_missing_code,
               CASE WHEN n.REC_TYPE IN ('B', 'D') THEN 1 ELSE 0 END                     AS end_dated
          FROM named n
    ),
    ranked AS (
        SELECT m.*,
               /* TIMELINE: VERSION_SEQ_NUM per CARE id in SRT_VALID_MEMBERS order (REC_TYPE descending) */
               CASE WHEN m.valid_member = 1
                    THEN ROW_NUMBER() OVER (PARTITION BY m.valid_member, m.CARE_ID ORDER BY m.REC_TYPE DESC) END
                                                                                        AS version_seq_num,
               fn_ors_helper08_common(m.fn_missing_code)                                AS fn_exception_code,
               fn_ors_helper04_common(m.fn_missing_code)                                AS fn_exception_desc,
               fn_ors_helper05_common(m.fn_missing_code)                                AS fn_exception_type,
               fn_ors_helper08_common(m.ln_missing_code)                                AS ln_exception_code,
               fn_ors_helper04_common(m.ln_missing_code)                                AS ln_exception_desc,
               fn_ors_helper05_common(m.ln_missing_code)                                AS ln_exception_type,
               CASE WHEN m.orig_rowid_object_desc = 'N' THEN m.TARGET_ID ELSE m.CARE_ID END AS mrg_care_id,
               /* BAD DATA: EXP_PTY_RLE_ALT_ID.SSN_OUT suppresses the default values */
               CASE WHEN m.SSN = 'U' OR m.SSN = 'N' THEN NULL ELSE m.SSN END            AS ssn_out,
               fn_ors_helper03_common(NULL, 'CRE', m.STATE)                             AS std_state_cd
          FROM members m
    ),
    -- the mapplets and rules of the de-duplicated members (Filt_DeDeup_Seq1 / FLTR_NULL_ALT_ID_SEQ1)
    dq AS (
        SELECT /*+ NO_MERGE */
               r.*,
               CASE WHEN r.version_seq_num = 1 THEN fn_dq_valid_gender(r.SEX, 'Indv', 'CRE') END         AS gd,
               CASE WHEN r.version_seq_num = 1 THEN fn_dq_valid_ethnicity(r.FEDETH, 'CRE') END           AS et,
               CASE WHEN r.version_seq_num = 1 THEN fn_dq_valid_race(r.RACE, 'CRE') END                  AS rc,
               -- rule_Phone_Std: only the number is linked (source system and usage type NULL)
               CASE WHEN r.version_seq_num = 1 AND r.PHONE IS NOT NULL THEN fn_dq_std_phone(r.PHONE, NULL, NULL) END
                                                                                                         AS ph,
               CASE WHEN r.version_seq_num = 1 THEN fn_dq_std_care_id(r.mrg_care_id) END                 AS ci,
               CASE WHEN r.version_seq_num = 1 THEN fn_dq_std_medicaid_id(r.RECIP_NO) END                AS md,
               CASE WHEN r.version_seq_num = 1 THEN fn_dq_valid_ssn(r.ssn_out) END                       AS sn,
               -- RTR_US_ADDRESSES.US_ADDRESSES (STD_STATE_CD <> '99' OR ISNULL) -> mplt_Global_Addr_Validation
               CASE WHEN r.version_seq_num = 1 AND (r.std_state_cd <> '99' OR r.std_state_cd IS NULL)
                    THEN fn_dq_valid_global_addr(r.STREET, NULL, r.CITY, r.STATE, r.ZIP || '-' || r.ZIPSUF, 'US',
                                                 'CRE') END                                              AS av,
               CASE WHEN r.std_state_cd <> '99' OR r.std_state_cd IS NULL THEN 1 ELSE 0 END             AS addr_us
          FROM ranked r
    ),
    -- lkp_ALT_ID_MSTR_REF_CODE: LOOKUP_CODE_VALUE of SRC_SYS CRE by source value (no code-type filter), any row
    alt_tp AS (
        SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE, l.MSTR_REF_LABEL, l.SRC_SYS,
               ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.CODE_TYPE) AS rn
          FROM LOOKUP_CODE_VALUE l
         WHERE l.SRC_SYS = 'CRE' AND l.SRC_CODE_VALUE IN ('CARE ID', 'Medicaid ID', 'SSN')
    ),
    flat AS (
        SELECT d.*,
               TO_CHAR(d.CARE_ID)                                                       AS pty_key,
               TO_CHAR(d.CARE_ID) || '|' || p_rle_bo_class_cd_member                    AS rle_key,
               /* TIMELINE: EXP_VALID_MEMBERS */
               CASE WHEN d.end_dated = 1 THEN d.CARE_LASTUP_DT - 1 ELSE d.CARE_LASTUP_DT END AS period_start,
               CASE WHEN d.end_dated = 1 THEN d.CARE_LASTUP_DT END                      AS period_end,
               CASE WHEN d.end_dated = 1 THEN 2 END                                     AS timeline_action,
               CASE WHEN d.end_dated = 1 THEN d.CARE_LASTUP_DT - 1 END                  AS period_reference_time,
               CASE WHEN d.end_dated = 1 THEN l_run_ts - INTERVAL '1' HOUR ELSE l_run_ts END AS last_update,
               /* TIMELINE: EXP_PTY_HOLD / EXP_PTY_RLE_HOLD (start + 1 day) */
               CASE WHEN d.end_dated = 1 THEN (d.CARE_LASTUP_DT - 1) + 1 END            AS pty_period_end,
               CASE WHEN d.end_dated = 1 THEN d.CARE_LASTUP_DT - 1 END                  AS pty_period_reference_time,
               NVL(d.CARE_LASTUP_DT, d.INSERT_DATE)                                     AS src_last_update,
               d.gd.mdm_gender_code                                                     AS mdm_gender_code,
               d.gd.gender_exception_code                                               AS gender_exception_code,
               d.gd.gender_exception_description                                        AS gender_exception_description,
               d.gd.gender_exception_type                                               AS gender_exception_type,
               d.et.mstr_code_value                                                     AS ethnicity_mstr,
               d.et.exception_code                                                      AS ethnicity_exception_code,
               d.et.exception_desc                                                      AS ethnicity_exception_desc,
               d.et.exception_type                                                      AS ethnicity_exception_type,
               d.rc.mstr_code_value                                                     AS race_mstr,
               d.rc.exception_code                                                      AS race_exception_code,
               d.rc.exception_desc                                                      AS race_exception_desc,
               d.rc.exception_type                                                      AS race_exception_type,
               d.ph.phone                                                               AS phone_std,
               fn_ors_helper08_common(d.ph.phone_exception_code)                        AS phone_exception_code,
               d.ph.phone_exception_type                                                AS phone_exception_type,
               d.ph.phone_exception_desc                                                AS phone_exception_desc,
               TO_CHAR(d.CARE_ID) || '|Member|Telephone|001|' || d.ph.phone             AS phn_key,
               /* VALIDATION: RTR_VALID_ADDRESS / RTR_VALID_NON_US_ADDRESSES */
               CASE WHEN d.addr_us = 1
                    THEN CASE WHEN (CASE WHEN fn_ors_helper01_common(d.av.mailability_score) = 1
                                         THEN TRUNC(TO_NUMBER(d.av.mailability_score)) END >= 3
                                    OR SUBSTR(d.av.match_code, 1, 1) NOT IN ('I', 'N'))
                                   AND d.av.state_fips_cd IS NOT NULL THEN 1 ELSE 0 END
                    ELSE CASE WHEN d.CITY IS NOT NULL AND d.STREET IS NOT NULL THEN 1 ELSE 0 END END AS addr_valid,
               CASE WHEN d.addr_us = 1 THEN d.av.delivery_address_line1 ELSE INITCAP(d.STREET) END AS a_line1,
               CASE WHEN d.addr_us = 1 THEN d.av.delivery_address_line2 END             AS a_line2,
               CASE WHEN d.addr_us = 1 THEN d.av.city ELSE INITCAP(d.CITY) END          AS a_city,
               CASE WHEN d.addr_us = 1 THEN d.av.state_fips_cd ELSE p_default_nonus_state_cd END AS a_state,
               CASE WHEN d.addr_us = 1 THEN d.av.county_fips_cd ELSE d.CNTY END         AS a_county_fips,
               CASE WHEN d.addr_us = 1 THEN d.av.country_iso2_char ELSE 'ZZ' END        AS a_country,
               CASE WHEN d.addr_us = 1 THEN d.av.zip_cd_5 ELSE d.ZIP END                AS a_postcode,
               CASE WHEN d.addr_us = 1 THEN d.av.zip_cd_4_extn ELSE d.ZIPSUF END        AS a_postcode_ext,
               d.av.geocoding_latitude                                                  AS a_latitude,
               d.av.geocoding_longitude                                                 AS a_longitude,
               d.av.mailability_score                                                   AS a_mailability_score,
               d.av.match_code                                                          AS a_match_code,
               d.av.address_type                                                        AS a_address_type,
               d.av.sub_building_number                                                 AS a_sub_building_number,
               d.av.sub_building_descriptor                                             AS a_sub_building_descriptor,
               d.av.sub_building_complete                                               AS a_sub_building_complete,
               d.av.building_number                                                     AS a_building_number,
               d.av.building_name                                                       AS a_building_name,
               d.av.residential_delivery_indicator                                      AS a_residential,
               d.av.geocoding_status                                                    AS a_geocoding_status,
               d.av.organization_name                                                   AS a_org_name,
               d.av.organization_descriptor                                             AS a_org_descriptor,
               CASE WHEN fn_ors_helper01_common(d.av.mailability_score) = 1
                    THEN TO_NUMBER(d.av.mailability_score) END                          AS a_dr_mailability_score,
               d.av.match_code_description                                              AS a_dr_error_desc,
               d.av.match_code                                                          AS a_dr_error_code,
               -- NRML_ALT_ID occurrences and lkp_ALT_ID_MSTR_REF_CODE
               d.ci.id_value                                                            AS care_alt_id,
               t1.MSTR_REF_CODE                                                         AS care_tp_cd,
               d.md.id_value                                                            AS medicaid_alt_id,
               d.md.exception_code                                                      AS medicaid_exception_code,
               d.md.exception_desc                                                      AS medicaid_exception_desc,
               d.md.exception_type                                                      AS medicaid_exception_type,
               t2.MSTR_REF_CODE                                                         AS medicaid_tp_cd,
               t2.MSTR_REF_LABEL                                                        AS medicaid_tp_lbl,
               t2.SRC_SYS                                                               AS medicaid_tp_sys,
               /* VALIDATION: exp_validate_ssn + Lkp_EXC_LOOKUP_CODE_VALUE_SSN (looked-up code) */
               fn_ors_helper08_common(CASE WHEN d.sn.ssn_status = 'Invalid' AND d.ssn_out IS NOT NULL
                                           THEN 'Invalid_SSN' END)                      AS ssn_exception_code,
               fn_ors_helper04_common(CASE WHEN d.sn.ssn_status = 'Invalid' AND d.ssn_out IS NOT NULL
                                           THEN 'Invalid_SSN' END)                      AS ssn_exception_desc,
               fn_ors_helper05_common(CASE WHEN d.sn.ssn_status = 'Invalid' AND d.ssn_out IS NOT NULL
                                           THEN 'Invalid_SSN' END)                      AS ssn_exception_type,
               t3.MSTR_REF_CODE                                                         AS ssn_tp_cd,
               t3.MSTR_REF_LABEL                                                        AS ssn_tp_lbl,
               t3.SRC_SYS                                                               AS ssn_tp_sys,
               TO_CHAR(d.CARE_ID) || '|' || p_rle_bo_class_cd_member || '|' || t1.MSTR_REF_CODE || '|' || d.ci.id_value
                                                                                        AS care_alt_key,
               TO_CHAR(d.CARE_ID) || '|' || p_rle_bo_class_cd_member || '|' || t2.MSTR_REF_CODE || '|' || d.md.id_value
                                                                                        AS medicaid_alt_key,
               TO_CHAR(d.CARE_ID) || '|' || p_rle_bo_class_cd_member || '|' || t3.MSTR_REF_CODE || '|' || d.ssn_out
                                                                                        AS ssn_alt_key
          FROM dq d
          LEFT JOIN alt_tp t1 ON t1.SRC_CODE_VALUE = 'CARE ID' AND t1.rn = 1
          LEFT JOIN alt_tp t2 ON t2.SRC_CODE_VALUE = 'Medicaid ID' AND t2.rn = 1
          LEFT JOIN alt_tp t3 ON t3.SRC_CODE_VALUE = 'SSN' AND t3.rn = 1
    )
    -- EXP_PTY_RLE_ADDR_HOLD.out_COUNTY_CD and the address key
    SELECT f.*,
           CASE WHEN f.a_state <> p_default_tx_state_cd THEN p_county_cd_nontx
                WHEN f.a_county_fips IS NULL THEN p_countycd_defaultall
                ELSE f.a_county_fips END                                                AS a_county,
           f.rle_key || '|' || p_physical_addr_type_cd                                  AS addr_key
      FROM flat f;
    sp_ors_helper02_common(c_mapping, 'insert (CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, '
                           || 'C_S_CRE_PTY_RLE_PHN, C_S_CRE_PTY_RLE_ALT_ID, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients;
/
