--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_FSS_Pty
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_FSS_Pty (workflow wf_FSS_Stage_Load).
--
-- Loads the FSS clients (V_FSS_ETL_SRC, last active registration) into C_S_FSS_PTY and C_S_FSS_PTY_RLE (both
-- truncated first) and logs demographic exceptions:
--   -> Flt_Remove_Inactive: party not in STG_FSS_PTY_INACTIVE_STS
--   -> name standardization (with the source suffix), gender, birth date, ethnicity (CD_HISPANIC), race
--      indicators, language, rule_Suffix_Std
--   -> Rtr_Exception: Valid_Party is TRUE (every active client loaded); each failed rule writes an
--      EXC_STG_BAD_REC_MEMB row - gender, ethnicity and race only for SOURCE_TYPE = 'CLIENT', birth date, language
--      and suffix for every row.
--
-- TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM); PERIOD_START_DATE =
-- DT_LAST_UPDATE on both targets.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_FSS_Pty (
    p_pty_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    p_rle_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_FSS_Pty';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
    l_sysdate  DATE := SYSDATE;
BEGIN
    sp_ors_helper01_common('C_S_FSS_PTY');
    sp_ors_helper01_common('C_S_FSS_PTY_RLE');

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_FSS_PTY
        WHEN 1 = 1 THEN
            INTO C_S_FSS_PTY
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, BIRTH_DT,
                  SRC_FULL_NM, ETHNCTY, SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM)
            VALUES (pkey_trim, DT_LAST_UPDATE /* TIMELINE */, 1 /* TIMELINE: VERSION_SEQ */, l_sysdate,
                    DT_LAST_UPDATE, pkey_trim, 1, p_pty_bo_class_cd_member, std_prfx_name, std_first_name,
                    std_mdl_name, std_lst_name, std_full_name, mdm_gender_code, DT_DOB, std_src_full_name,
                    ethnicity_mstr, CD_HISPANIC, mdm_race_cd, src_race_ind_list, DT_LAST_UPDATE, language_mstr,
                    std_suffix)
        -- Rtr_Exception.Valid_Party -> Write_C_S_FSS_PTY_RLE
        WHEN 1 = 1 THEN
            INTO C_S_FSS_PTY_RLE
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
            VALUES (pkey_trim || '|' || p_rle_bo_class_cd_member, DT_LAST_UPDATE /* TIMELINE */,
                    1 /* TIMELINE: VERSION_SEQ */, l_sysdate, DT_LAST_UPDATE,
                    pkey_trim || '|' || p_rle_bo_class_cd_member, 1, pkey_trim, p_rle_bo_class_cd_member,
                    DT_LAST_UPDATE)
        -- Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN gender_exception_description IS NOT NULL AND SOURCE_TYPE = 'CLIENT' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME)
            VALUES ('FSS', gender_exception_type, gender_exception_code, gender_exception_description, 'Gender',
                    CD_GENDER, c_mapping, PTY_SRC_KEY, ID_CLIENT, CD_GENDER, DT_DOB, l_run_ts, NM_FIRST, NM_MIDDLE,
                    NM_LAST)
        -- Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
        WHEN birth_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES ('FSS', PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
                    l_run_ts, c_mapping, CD_GENDER, birth_attribute_name, ID_CLIENT, std_prfx_name, NM_FIRST,
                    NM_LAST, NM_MIDDLE, TO_CHAR(DT_DOB, 'MM/DD/YYYY'), DT_DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
        WHEN ethnicity_exception_code IS NOT NULL AND SOURCE_TYPE = 'CLIENT' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (l_run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    'Ethnicity_Cd', CD_GENDER, PTY_SRC_KEY, 'FSS', NM_FIRST, std_lst_name, std_mdl_name, c_mapping,
                    DT_DOB, DT_LAST_UPDATE, ID_CLIENT, CD_HISPANIC)
        -- Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
        WHEN race_exception_desc IS NOT NULL AND SOURCE_TYPE = 'CLIENT' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (ID_CLIENT, PTY_SRC_KEY, 'FSS', race_exception_cd, race_exception_desc, race_exception_type,
                    l_run_ts, NM_FIRST, std_mdl_name, std_lst_name, CD_GENDER, DT_DOB, 'Race_Cd', std_prfx_name,
                    DT_LAST_UPDATE, c_mapping, src_race_ind_list)
        -- Rtr_Exception.Invalid_Language -> Write_Invalid_Party_Language
        WHEN language_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, PERIOD_START_DATE)
            VALUES ('FSS', PTY_SRC_KEY, ID_CLIENT, language_exception_type, language_exception_code,
                    language_exception_desc, l_run_ts, NM_FIRST, std_mdl_name, std_lst_name, std_birth_date,
                    CD_GENDER, 'Language_Cd', LANGUAGE_CD, c_mapping, DT_LAST_UPDATE)
        -- Rtr_Exception.Invalid_Suffix -> Exp_Invalid_Suffix -> Write_Invalid_Party_Suffix
        WHEN suffix_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, ALIAS_SUFFIX, BIRTH_DATE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, MAPPING_NAME)
            VALUES ('FSS', PTY_SRC_KEY, ID_CLIENT, suffix_exception_type, suffix_exception_code,
                    suffix_exception_desc, l_run_ts, NM_FIRST, NM_MIDDLE, NM_LAST, CD_SUFFIX, std_suffix,
                    birth_attribute_value, 'Name Suffix', CD_SUFFIX, c_mapping)
    WITH
    -- Read_V_FSS_ETL_SRC (source filter; the commented-out testing filter is not applied)
    src AS (
        SELECT v.SOURCE_TYPE, v.DT_LAST_UPDATE, v.PTY_SRC_KEY, v.ID_CLIENT, v.NM_FIRST, v.NM_LAST, v.NM_MIDDLE,
               v.DT_DOB, v.CD_GENDER, v.LANGUAGE_CD, v.CD_HISPANIC, v.RACE_AN, v.RACE_ASIAN, v.RACE_AA,
               v.RACE_WHITE, v.RACE_PI, v.CD_SUFFIX
          FROM V_FSS_ETL_SRC v
         WHERE v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y'
    ),
    -- Lookup_STG_FSS_PTY_INACTIVE_STS + Flt_Remove_Inactive
    active AS (
        SELECT s.*
          FROM src s
         WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = s.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    dq AS (
        SELECT /*+ NO_MERGE */
               a.*,
               fn_dq_std_name_indv_member(a.NM_FIRST, a.NM_MIDDLE, a.NM_LAST,
                   LTRIM(RTRIM(a.NM_FIRST || CASE WHEN a.NM_MIDDLE IS NOT NULL THEN ' ' || LTRIM(RTRIM(a.NM_MIDDLE)) END
                               || ' ' || LTRIM(a.NM_LAST))),
                   NULL, a.CD_SUFFIX, NULL, NULL, 'FSS')                                AS nm,
               fn_dq_valid_gender(a.CD_GENDER, 'Indv', 'FSS')                           AS gd,
               fn_dq_valid_birth_date(a.DT_DOB, 'Indv', 'FSS')                          AS bd,
               fn_dq_valid_ethnicity(a.CD_HISPANIC, 'FSS')                              AS et,
               fn_dq_valid_race_ind(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
               fn_dq_valid_language(a.LANGUAGE_CD, 'FSS')                               AS lg,
               fn_dq_std_suffix(a.CD_SUFFIX, 'FSS')                                     AS sx
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
           d.bd.attribute_value               AS birth_attribute_value,
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
           d.lg.exception_type                AS language_exception_type,
           d.sx.standardized_suffix           AS std_suffix,
           d.sx.suffix_exception_code         AS suffix_exception_code,
           d.sx.suffix_exception_type         AS suffix_exception_type,
           d.sx.suffix_exception_desc         AS suffix_exception_desc
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_FSS_PTY, C_S_FSS_PTY_RLE, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_FSS_Pty;
/
