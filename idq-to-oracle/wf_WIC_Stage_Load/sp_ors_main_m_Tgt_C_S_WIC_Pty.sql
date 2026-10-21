--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_WIC_Pty
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_WIC_Pty (workflow wf_WIC_Stage_Load).
--
-- Loads the WIC parties (V_WIC_ETL_SRC) into C_S_WIC_PTY and C_S_WIC_PTY_RLE (both truncated first) and logs
-- demographic exceptions:
--   -> Flt_Remove_Inactive: party not in STG_WIC_PTY_INACTIVE_STS
--   -> name standardization, gender, birth date, ethnicity, race indicators, language
--   -> Rtr_Exception: Valid_Party is TRUE (every active party loaded); each failed rule writes an
--      EXC_STG_BAD_REC_MEMB row - gender, ethnicity and race only for SOURCE_TABLE = 'CLIENT', birth date and
--      language for every row.
-- Birth weight in grams is BIRTH_WT_OZ * 28.35 (ounces only, per the 3/14/2025 change).
--
-- TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM); PERIOD_START_DATE = DATEKEY.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_WIC_Pty (
    p_pty_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    p_rle_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_WIC_Pty';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP()
    l_sysdate  DATE := SYSDATE;
BEGIN
    sp_ors_helper01_common('C_S_WIC_PTY');
    sp_ors_helper01_common('C_S_WIC_PTY_RLE');

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_WIC_PTY
        WHEN 1 = 1 THEN
            INTO C_S_WIC_PTY
                 (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND, PTY_BO_CLASS_CD,
                  BIRTH_WGHT_GRMS, PERIOD_START_DATE, CREATE_DATE, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD,
                  BIRTH_DT, SRC_RACE_CD, RACE_CD, ETHNCTY, SRC_ETHNCTY, PRFRD_LANG_CD, SRC_LAST_UPD_DT,
                  SRC_PRFRD_LANG_CD, SRC_FULL_NM)
            VALUES (pkey_trim, 1 /* TIMELINE: VERSION_SEQ */, l_sysdate, pkey_trim, 1, p_pty_bo_class_cd_member,
                    BIRTH_WT_OZ * 28.35, DATEKEY /* TIMELINE */, DATEKEY, std_prfx_name, std_first_name,
                    std_mdl_name, std_lst_name, std_full_name, mdm_gender_code, DOB, src_race_ind_list, mdm_race_cd,
                    ethnicity_mstr, ETHNICITY, language_mstr, DATEKEY, LANGUAGE_CD, std_src_full_name)
        -- Rtr_Exception.Valid_Party -> Write_C_S_WIC_PTY_RLE
        WHEN 1 = 1 THEN
            INTO C_S_WIC_PTY_RLE
                 (PKEY_SRC_OBJECT, SRC_ROWID, RLE_BO_CLASS_CD, PTY_FK, VERSION_SEQ, LAST_UPDATE_DATE, HUB_STATE_IND,
                  CREATE_DATE, PERIOD_START_DATE, SRC_LAST_UPD_DT)
            VALUES (pkey_trim || '|' || p_rle_bo_class_cd_member, pkey_trim || '|' || p_rle_bo_class_cd_member,
                    p_rle_bo_class_cd_member, pkey_trim, 1 /* TIMELINE: VERSION_SEQ */, l_sysdate, 1, DATEKEY,
                    DATEKEY /* TIMELINE */, DATEKEY)
        -- Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN gender_exception_description IS NOT NULL AND SOURCE_TABLE = 'CLIENT' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME)
            VALUES ('WIC', gender_exception_type, gender_exception_code, gender_exception_description, 'Gender',
                    GENDER, c_mapping, PTY_SRC_KEY, ID, GENDER, DOB, l_run_ts, FIRST_NAME, MIDDLE_NAME, LAST_NAME)
        -- Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
        WHEN birth_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES ('WIC', PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
                    l_run_ts, c_mapping, GENDER, birth_attribute_name, ID, std_prfx_name, FIRST_NAME, LAST_NAME,
                    MIDDLE_NAME, TO_CHAR(DOB, 'MM/DD/YYYY'), DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
        WHEN ethnicity_exception_code IS NOT NULL AND SOURCE_TABLE = 'CLIENT' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (l_run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    'Ethnicity_Cd', GENDER, PTY_SRC_KEY, 'WIC', FIRST_NAME, std_lst_name, std_mdl_name, c_mapping,
                    DOB, DATEKEY, ID, ETHNICITY)
        -- Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
        WHEN race_exception_desc IS NOT NULL AND SOURCE_TABLE = 'CLIENT' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (ID, PTY_SRC_KEY, 'WIC', race_exception_cd, race_exception_desc, race_exception_type, l_run_ts,
                    FIRST_NAME, std_mdl_name, std_lst_name, GENDER, DOB, 'Race_Cd', std_prfx_name, DATEKEY,
                    c_mapping, src_race_ind_list)
        -- Rtr_Exception.Invalid_Language -> Write_Invalid_Party_Language
        WHEN language_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, PERIOD_START_DATE)
            VALUES ('WIC', PTY_SRC_KEY, ID, language_exception_type, language_exception_code,
                    language_exception_desc, l_run_ts, FIRST_NAME, std_mdl_name, std_lst_name, std_birth_date,
                    GENDER, 'Language_Cd', LANGUAGE_CD, c_mapping, DATEKEY)
    WITH
    -- Read_V_WIC_ETL_SRC + Lookup_STG_WIC_PTY_INACTIVE_STS + Flt_Remove_Inactive
    active AS (
        SELECT v.SOURCE_TABLE, v.DATEKEY, v.LOAD_DATE, v.ID, v.PTY_SRC_KEY, v.FIRST_NAME, v.LAST_NAME, v.MIDDLE_NAME,
               v.DOB, v.GENDER, v.BIRTH_WT_LB, v.BIRTH_WT_OZ, v.LANGUAGE_CD, v.ETHNICITY, v.RACE_WHITE_IND,
               v.RACE_AA_IND, v.RACE_ASIAN_IND, v.RACE_PI_IND, v.RACE_AN_IND
          FROM V_WIC_ETL_SRC v
         WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    dq AS (
        SELECT /*+ NO_MERGE */
               a.*,
               fn_dq_std_name_indv_member(a.FIRST_NAME, a.MIDDLE_NAME, a.LAST_NAME,
                   LTRIM(RTRIM(a.FIRST_NAME || CASE WHEN a.MIDDLE_NAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(a.MIDDLE_NAME)) END
                               || ' ' || LTRIM(a.LAST_NAME))),
                   NULL, NULL, NULL, NULL, 'WIC')                                       AS nm,
               fn_dq_valid_gender(a.GENDER, 'Indv', 'WIC')                              AS gd,
               fn_dq_valid_birth_date(a.DOB, 'Indv', 'WIC')                             AS bd,
               fn_dq_valid_ethnicity(a.ETHNICITY, 'WIC')                                AS et,
               fn_dq_valid_race_ind(a.RACE_WHITE_IND, a.RACE_AA_IND, a.RACE_ASIAN_IND, a.RACE_PI_IND,
                                    a.RACE_AN_IND)                                      AS rc,
               fn_dq_valid_language(a.LANGUAGE_CD, 'WIC')                               AS lg
          FROM active a
    )
    SELECT d.*,
           LTRIM(RTRIM(d.PTY_SRC_KEY))        AS pkey_trim,
           d.nm.first_name                    AS std_first_name,
           d.nm.mdl_name                      AS std_mdl_name,
           d.nm.lst_name                      AS std_lst_name,
           d.nm.full_name                     AS std_full_name,
           d.nm.src_full_name                 AS std_src_full_name,
           d.nm.prfx_name                     AS std_prfx_name,
           d.gd.mdm_gender_code               AS mdm_gender_code,
           d.gd.gender_exception_code         AS gender_exception_code,
           d.gd.gender_exception_description  AS gender_exception_description,
           d.gd.gender_exception_type         AS gender_exception_type,
           d.bd.birth_date                    AS std_birth_date,
           d.bd.exception_code                AS birth_exception_code,
           d.bd.exception_description         AS birth_exception_description,
           d.bd.exception_type                AS birth_exception_type,
           d.bd.attribute_name                AS birth_attribute_name,
           d.et.mstr_code_value               AS ethnicity_mstr,
           d.et.exception_code                AS ethnicity_exception_code,
           d.et.exception_desc                AS ethnicity_exception_desc,
           d.et.exception_type                AS ethnicity_exception_type,
           d.rc.mdm_race_cd                   AS mdm_race_cd,
           d.rc.src_race_ind_list             AS src_race_ind_list,
           d.rc.exception_cd                  AS race_exception_cd,
           d.rc.exception_desc                AS race_exception_desc,
           d.rc.exception_type                AS race_exception_type,
           d.lg.mstr_code_value               AS language_mstr,
           d.lg.exception_code                AS language_exception_code,
           d.lg.exception_desc                AS language_exception_desc,
           d.lg.exception_type                AS language_exception_type
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_WIC_PTY, C_S_WIC_PTY_RLE, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_WIC_Pty;
/
