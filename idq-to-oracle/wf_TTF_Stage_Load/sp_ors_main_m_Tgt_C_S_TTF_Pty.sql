--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TTF_Pty
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TTF_Pty (workflow wf_TTF_Stage_Load).
--
-- Loads the TTF clients (V_TTF_ETL_SRC) into C_S_TTF_PTY and C_S_TTF_PTY_RLE (both truncated first) and logs
-- demographic exceptions:
--   -> Flt_Remove_Inactive: party (PTY_SRC_KEY) not in STG_TTF_PTY_INACTIVE_STS
--   -> Expression: gender from SEXID (33 -> F, 34 -> M, else U); ethnicity = '55' when RACEETHNICITYID = '55'
--   -> name standardization, gender, birth date, ethnicity, race by code (mplt_Race_Validation on RACEETHNICITYID)
--   -> Rtr_Exception: Valid_Party is TRUE (every active client loaded); birth date, gender, ethnicity and race
--      failures each write an EXC_STG_BAD_REC_MEMB row for every row (no source-table condition in TTF).
--      The Invalid_Language / Invalid_Suffix groups test ports that are not fed in IDQ and have no target: no rows.
--
-- TIMELINE: VERSION_SEQ hard-coded to 1; party PERIOD_START_DATE = run start ($sys.MappingRunStartTime), role
-- PERIOD_START_DATE = SUBMITDATE.
-- PRFRD_LANG_CD and SFX_NM are linked to unfed ports in IDQ (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TTF_Pty (
    p_pty_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    p_rle_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TTF_Pty';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
    l_sysdate  DATE := SYSDATE;
BEGIN
    sp_ors_helper01_common('C_S_TTF_PTY');
    sp_ors_helper01_common('C_S_TTF_PTY_RLE');

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_TTF_PTY
        WHEN 1 = 1 THEN
            INTO C_S_TTF_PTY
                 (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, HUB_STATE_IND,
                  PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, SRC_FULL_NM, ETHNCTY,
                  SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM, PERIOD_START_DATE,
                  BIRTH_DT)
            VALUES (pkey_trim, 1 /* TIMELINE: VERSION_SEQ */, l_sysdate, SUBMITDATE, pkey_trim, 1,
                    p_pty_bo_class_cd_member, std_prfx_name, std_first_name, std_mdl_name, std_lst_name,
                    std_full_name, mdm_gender_code, std_src_full_name, ethnicity_mstr, ethnicity, race_mstr,
                    RACEETHNICITYID, SUBMITDATE, NULL /* unfed */, NULL /* unfed */,
                    l_run_ts /* TIMELINE: $sys.MappingRunStartTime */, std_birth_date)
        -- Rtr_Exception.Valid_Party -> Write_C_S_TTF_PTY_RLE
        WHEN 1 = 1 THEN
            INTO C_S_TTF_PTY_RLE
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
            VALUES (pkey_trim || '|' || p_rle_bo_class_cd_member, SUBMITDATE /* TIMELINE */,
                    1 /* TIMELINE: VERSION_SEQ */, l_sysdate, SUBMITDATE,
                    pkey_trim || '|' || p_rle_bo_class_cd_member, 1, pkey_trim, p_rle_bo_class_cd_member, SUBMITDATE)
        -- Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN gender_exception_description IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME)
            VALUES ('TTF', gender_exception_type, gender_exception_code, gender_exception_description, 'Gender',
                    gender, c_mapping, PTY_SRC_KEY, CLIENTS_ID, gender, DOB, l_run_ts, FIRSTNAME, MIDDLENAME,
                    LASTNAME)
        -- Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
        WHEN birth_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES ('TTF', PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
                    l_run_ts, c_mapping, gender, birth_attribute_name, CLIENTS_ID, std_prfx_name, FIRSTNAME,
                    LASTNAME, MIDDLENAME, TO_CHAR(DOB, 'MM/DD/YYYY'), DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
        WHEN ethnicity_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (l_run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    'Ethnicity_Cd', gender, PTY_SRC_KEY, 'TTF', FIRSTNAME, std_lst_name, std_mdl_name, c_mapping,
                    DOB, SUBMITDATE, CLIENTS_ID, ethnicity)
        -- Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
        WHEN race_exception_desc IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (CLIENTS_ID, PTY_SRC_KEY, 'TTF', race_exception_code, race_exception_desc, race_exception_type,
                    l_run_ts, FIRSTNAME, std_mdl_name, std_lst_name, gender, DOB, 'Race_Cd', std_prfx_name,
                    SUBMITDATE, c_mapping, RACEETHNICITYID)
    WITH
    -- Read_V_TTF_ETL_SRC + Expression + Lookup_STG_TTF_PTY_INACTIVE_STS + Flt_Remove_Inactive
    active AS (
        SELECT v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.SUBMITDATE, v.SEXID,
               v.RACEETHNICITYID, v.PTY_SRC_KEY, v.LOAD_DATE,
               DECODE(v.SEXID, '33', 'F', '34', 'M', 'U')                        AS gender,
               CASE WHEN v.RACEETHNICITYID = '55' THEN '55' END                  AS ethnicity
          FROM V_TTF_ETL_SRC v
         WHERE NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i
                            WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                              AND i.DEACTIVATION_STS IS NOT NULL)
    ),
    dq AS (
        SELECT /*+ NO_MERGE */
               a.*,
               fn_dq_std_name_indv_member(a.FIRSTNAME, a.MIDDLENAME, a.LASTNAME,
                   LTRIM(RTRIM(a.FIRSTNAME || CASE WHEN a.MIDDLENAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(a.MIDDLENAME)) END
                               || ' ' || LTRIM(a.LASTNAME))),
                   NULL, NULL, NULL, NULL, 'TTF')                         AS nm,
               fn_dq_valid_gender(a.gender, 'Indv', 'TTF')                AS gd,
               fn_dq_valid_birth_date(a.DOB, 'Indv', 'TTF')               AS bd,
               fn_dq_valid_ethnicity(a.ethnicity, 'TTF')                  AS et,
               fn_dq_valid_race(a.RACEETHNICITYID, 'TTF')                 AS rc
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
           d.rc.mstr_code_value               AS race_mstr,
           d.rc.exception_code                AS race_exception_code,
           d.rc.exception_desc                AS race_exception_desc,
           d.rc.exception_type                AS race_exception_type
      FROM dq d;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TTF_PTY, C_S_TTF_PTY_RLE, exceptions)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TTF_Pty;
/
