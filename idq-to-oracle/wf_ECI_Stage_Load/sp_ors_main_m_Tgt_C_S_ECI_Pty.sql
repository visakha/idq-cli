--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_ECI_Pty
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_ECI_Pty (workflow wf_ECI_Stage_Load).
--
-- Loads the ECI child and family parties of the delta into C_S_ECI_PTY and C_S_ECI_PTY_RLE (both truncated first)
-- and logs demographic exceptions:
--   Read_STG_ECI_D_CHILD_AND_FAMILY (custom SQL)
--     -> Flt_Remove_Inactive: IsNull(DEACTIVATION_STS) on STG_ECI_PTY_INACTIVE_STS (the stored condition is
--        "--not IsNull(...)"; "--not" is an IDQ comment, so ACTIVE parties are kept)
--     -> name standardization, gender, birth date, ethnicity, race indicators, language (fn_dq_* functions)
--     -> Rtr_Exception: Valid_Party is TRUE, so every active party is loaded; each failed rule additionally writes
--        one EXC_STG_BAD_REC_MEMB row (ethnicity, race and language only for child rows).
-- The source read also stores a filter on five child ids; it is not part of the custom query and is ignored, as in
-- IDQ (custom query mode).
--
-- TIMELINE (stale MDM timeline, ported here as IDQ does it):
--   * VERSION_SEQ is hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM = 1) on both targets.
--   * exp_Party_Consolidation also computes DUP_RANK and an MD5 of the demographics for the timeline; neither is
--     written by IDQ, so they are not computed here.
--   * PERIOD_START_DATE: party = source DATE_MODIFIED (DATE_MODIFIED, else DATE_CREATED); role = DATE_CREATED.
--
-- Exception rows carry MAPPING_NAME 'm_Tgt_C_S_ECI_Pty_OnGoing' (literal in the IDQ expressions).
-- Target load order (IDQ): Write_Invalid_Party_Ethnicity before Write_Invalid_Party_Race; the INTO clauses keep that
-- order.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_ECI_Pty (
    p_pty_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    p_rle_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
IS
    c_mapping      CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty';
    c_exc_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty_OnGoing';
    l_run_ts       TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP() of RUN_DATE
    l_sysdate      DATE := SYSDATE;             -- SYSDATE of LAST_UPDATE_DATE
BEGIN
    sp_ors_helper01_common('C_S_ECI_PTY');
    sp_ors_helper01_common('C_S_ECI_PTY_RLE');

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_ECI_PTY
        WHEN 1 = 1 THEN
            INTO C_S_ECI_PTY
                 (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
                  PTY_BO_CLASS_CD, PRFX_NM, FULL_NM, LST_NM, MDL_NM, FRST_NM, GNDR_CD, BIRTH_DT, SRC_FULL_NM,
                  SRC_LAST_UPD_DT, BIRTH_WGHT_GRMS, HUB_STATE_IND, SRC_ETHNCTY, ETHNCTY, RACE_CD, PRFRD_LANG_CD,
                  SRC_PRFRD_LANG_CD, SRC_RACE_CD, PERIOD_START_DATE)
            VALUES (pkey_trim, 1 /* TIMELINE: VERSION_SEQ hard-coded */, l_sysdate, MODIFIED_BY, DATE_CREATED,
                    CREATED_BY, pkey_trim, p_pty_bo_class_cd_member, std_prfx_name, std_full_name, std_lst_name,
                    std_mdl_name, std_first_name, mdm_gender_code, std_birth_date, std_src_full_name, DATE_MODIFIED,
                    BIRTH_WT_LB * 453.6 + BIRTH_WT_OZ * 28.35, 1, ETHNICITY, ethnicity_mstr, mdm_race_cd,
                    language_mstr, LANGUAGE_CD, src_race_ind_list, DATE_MODIFIED /* TIMELINE */)
        -- Rtr_Exception.Valid_Party -> Write_C_S_ECI_PTY_RLE
        WHEN 1 = 1 THEN
            INTO C_S_ECI_PTY_RLE
                 (PKEY_SRC_OBJECT, LAST_UPDATE_DATE, CREATOR, CREATE_DATE, VERSION_SEQ, PTY_FK, SRC_LAST_UPD_DT,
                  RLE_BO_CLASS_CD, PERIOD_START_DATE, HUB_STATE_IND, SRC_ROWID)
            VALUES (pkey_trim || '|' || p_rle_bo_class_cd_member, l_sysdate, CREATED_BY, DATE_CREATED,
                    1 /* TIMELINE: VERSION_SEQ hard-coded */, pkey_trim, DATE_MODIFIED, p_rle_bo_class_cd_member,
                    DATE_CREATED /* TIMELINE */, 1, pkey_trim || '|' || p_rle_bo_class_cd_member)
        -- Rtr_Exception.Invalid_Gender_Code -> Exp_Invalid_Gender -> Write_Invalid_Party_Gender
        WHEN gender_exception_description IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE)
            VALUES (src_system, gender_exception_type, gender_exception_code, gender_exception_description,
                    'Gender', GENDER, c_exc_mapping, pkey_src_object, ID, GENDER, DOB, l_run_ts)
        -- Rtr_Exception.Invalid_Birth_Date -> Exp_Invalid_DOB -> Write_Invalid_Party_DOB
        WHEN birth_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES (src_system, pkey_src_object, birth_exception_code, birth_exception_description,
                    birth_exception_type, l_run_ts, c_exc_mapping, GENDER, birth_attribute_name, ID, std_prfx_name,
                    FIRST_NAME, LAST_NAME, MIDDLE_INITIAL, TO_CHAR(DOB, 'MM/DD/YYYY'), DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Exp_Load_Ethnicity_Exceptions -> Write_Invalid_Party_Ethnicity
        WHEN ethnicity_exception_code IS NOT NULL AND SOURCE_TABLE = 'ECI_CHILD' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (l_run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    'Ethnicity_Cd', GENDER, pkey_src_object, src_system, FIRST_NAME, std_lst_name, std_mdl_name,
                    c_exc_mapping, DOB, DATE_CREATED, ID, ETHNICITY)
        -- Rtr_Exception.Invalid_Race -> Exp_Load_Race_Exceptions -> Write_Invalid_Party_Race
        WHEN race_exception_desc IS NOT NULL AND SOURCE_TABLE = 'ECI_CHILD' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (ID, pkey_src_object, src_system, race_exception_cd, race_exception_desc, race_exception_type,
                    l_run_ts, FIRST_NAME, std_mdl_name, std_lst_name, GENDER, DOB, 'Race_Cd', std_prfx_name,
                    DATE_CREATED, c_exc_mapping, src_race_ind_list)
        -- Rtr_Exception.Invalid_Language -> Exp_Load_Language_Exceptions -> Write_Invalid_Party_Language
        WHEN language_exception_code IS NOT NULL AND SOURCE_TABLE = 'ECI_CHILD' THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, PERIOD_START_DATE)
            VALUES (src_system, pkey_src_object, ID, language_exception_type, language_exception_code,
                    language_exception_desc, l_run_ts, FIRST_NAME, std_mdl_name, std_lst_name, std_birth_date,
                    GENDER, 'Language_Cd', LANGUAGE_CD, c_exc_mapping, DATE_CREATED)
    WITH
    -- Read_STG_ECI_D_CHILD_AND_FAMILY (custom SQL, query mode SEMI)
    src AS (
        SELECT 'ECI_CHILD' AS SOURCE_TABLE, child.ID_CHILD AS ID, child.CHILD_SSN, child.FIRST_NAME, child.LAST_NAME,
               child.MIDDLE_INITIAL, child.DOB, child.GESTATION_AGE, child.GENDER, child.BIRTH_WT_LB,
               child.BIRTH_WT_OZ, child.INTERPRET_IND, child.LANGUAGE_CD, child.RACE_CD, child.DATE_CREATED,
               COALESCE(child.DATE_MODIFIED, child.DATE_CREATED) AS DATE_MODIFIED, child.MODIFIED_BY,
               child.CREATED_BY, child.ETHNICITY, child.RACE_WHITE, child.RACE_AA, child.RACE_ASIAN, child.RACE_PI,
               child.RACE_AN, child.LOAD_DATE
          FROM STG_ECI_D_CHILD child
        UNION ALL
        SELECT 'ECI_FAMILY', fam.ID_FAMILY, NULL, fam.FIRST_NAME, fam.LAST_NAME, fam.MIDDLE_INITIAL, fam.DOB, NULL,
               fam.GENDER, NULL, NULL, NULL, NULL, NULL, fam.DATE_CREATED,
               COALESCE(fam.DATE_MODIFIED, fam.DATE_CREATED), fam.MODIFIED_BY, fam.CREATED_BY, NULL, NULL, NULL,
               NULL, NULL, NULL, fam.LOAD_DATE
          FROM STG_ECI_D_FAMILY fam
    ),
    -- Exp_ECI_Data_Load
    exp_load AS (
        SELECT s.*,
               LPAD(s.ID, 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END  AS pkey_src_object,
               'Indv' AS party_type,
               'ECI'  AS src_system,
               LTRIM(RTRIM(s.FIRST_NAME
                     || CASE WHEN s.MIDDLE_INITIAL IS NOT NULL THEN ' ' || LTRIM(RTRIM(s.MIDDLE_INITIAL)) END
                     || ' ' || LTRIM(s.LAST_NAME)))                                       AS src_full_name
          FROM src s
    ),
    -- Lkp_STG_ECI_PTY_INACTIVE_STS + Flt_Remove_Inactive
    active AS (
        SELECT e.*
          FROM exp_load e
         WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = e.pkey_src_object AND i.ROWID_SYSTEM = e.src_system
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    -- mapplet calls (one per row)
    dq AS (
        SELECT /*+ NO_MERGE */
               a.*,
               fn_dq_std_name_indv_member(a.FIRST_NAME, a.MIDDLE_INITIAL, a.LAST_NAME, a.src_full_name,
                                          NULL, NULL, NULL, NULL, a.src_system)     AS nm,
               fn_dq_valid_gender(a.GENDER, a.party_type, a.src_system)            AS gd,
               fn_dq_valid_birth_date(a.DOB, a.party_type, a.src_system)           AS bd,
               fn_dq_valid_ethnicity(a.ETHNICITY, a.src_system)                    AS et,
               fn_dq_valid_race_ind(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
               fn_dq_valid_language(a.LANGUAGE_CD, a.src_system)                   AS lg
          FROM active a
    )
    -- Exp_Consolidate_Exceptions
    SELECT d.*,
           LTRIM(RTRIM(d.pkey_src_object))  AS pkey_trim,          -- exp_Party_Consolidation.o_PKEY_SRC_OBJECT
           d.nm.first_name                  AS std_first_name,
           d.nm.mdl_name                    AS std_mdl_name,
           d.nm.lst_name                    AS std_lst_name,
           d.nm.full_name                   AS std_full_name,
           d.nm.src_full_name               AS std_src_full_name,
           d.nm.prfx_name                   AS std_prfx_name,
           d.gd.mdm_gender_code             AS mdm_gender_code,
           d.gd.gender_exception_code       AS gender_exception_code,
           d.gd.gender_exception_description AS gender_exception_description,
           d.gd.gender_exception_type       AS gender_exception_type,
           d.bd.birth_date                  AS std_birth_date,
           d.bd.exception_code              AS birth_exception_code,
           d.bd.exception_description       AS birth_exception_description,
           d.bd.exception_type              AS birth_exception_type,
           d.bd.attribute_name              AS birth_attribute_name,
           d.et.mstr_code_value             AS ethnicity_mstr,
           d.et.exception_code              AS ethnicity_exception_code,
           d.et.exception_desc              AS ethnicity_exception_desc,
           d.et.exception_type              AS ethnicity_exception_type,
           d.rc.mdm_race_cd                 AS mdm_race_cd,
           d.rc.src_race_ind_list           AS src_race_ind_list,
           d.rc.exception_cd                AS race_exception_cd,
           d.rc.exception_desc              AS race_exception_desc,
           d.rc.exception_type              AS race_exception_type,
           d.lg.mstr_code_value             AS language_mstr,
           d.lg.exception_code              AS language_exception_code,
           d.lg.exception_desc              AS language_exception_desc,
           d.lg.exception_type              AS language_exception_type
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_ECI_PTY, C_S_ECI_PTY_RLE, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_ECI_Pty;
/
