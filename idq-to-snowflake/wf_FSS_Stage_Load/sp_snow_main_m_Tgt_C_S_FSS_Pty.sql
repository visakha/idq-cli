--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_FSS_Pty
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty (workflow wf_FSS_Stage_Load).
--
-- Loads the FSS clients (V_FSS_ETL_SRC, last active registration) into C_S_FSS_PTY and C_S_FSS_PTY_RLE (insert only,
-- never truncated) and logs demographic exceptions:
--   -> Flt_Remove_Inactive: party not in STG_FSS_PTY_INACTIVE_STS
--   -> name standardization (with the source suffix), gender, birth date, ethnicity (CD_HISPANIC), race
--      indicators, language, rule_Suffix_Std
--   -> Rtr_Exception: Valid_Party is TRUE (every active client loaded); each failed rule writes an
--      EXC_STG_BAD_REC_MEMB row - gender, ethnicity and race only for SOURCE_TYPE = 'CLIENT', birth date, language
--      and suffix for every row.
--
-- VALIDATION (common/01_snow_common_functions.sql): fn_snow_helper15_common name (suffix looked up with CODE_TYPE
--   'SUFFIX'), fn_snow_helper17_common gender, fn_snow_helper16_common birth date, fn_snow_helper18_common
--   ethnicity / language (V_LOOKUP_CODE_VALUE ETHNICITY / LANGUAGE_CD), fn_snow_helper19_common race indicators,
--   fn_snow_helper20_common rule_Suffix_Std (V_LOOKUP_CODE_VALUE WITHOUT a code-type filter).
-- BAD DATA: an exception never rejects the client: it is loaded AND logged. C_S_FSS_PTY.BIRTH_DT is the source DOB
--   (IDQ links the source port, not the mapplet output, so a future birth date is still loaded); the language
--   exception row writes the mapplet's birth date (NULL for a future one). Ethnicity, race and language exceptions
--   write the looked-up code and are routed on it (unconfigured code = no row); gender is routed on the looked-up
--   description. Unique keys Snowflake does not enforce are applied: C_S_FSS_PTY, C_S_FSS_PTY_RLE (PKEY_SRC_OBJECT,
--   VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM); PERIOD_START_DATE =
--   DT_LAST_UPDATE on both targets.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_FSS_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_FSS_Pty';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSDATE
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_FSS_PTY, C_S_FSS_PTY_RLE. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_FSS_PTY
        WHEN uq_pty THEN
            INTO C_S_FSS_PTY
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, BIRTH_DT,
                  SRC_FULL_NM, ETHNCTY, SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM)
            VALUES (pkey_trim, DT_LAST_UPDATE, version_seq, run_ts, DT_LAST_UPDATE, pkey_trim, hub_state_ind,
                    pty_bo_class_cd, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name,
                    mdm_gender_code, DT_DOB, std_src_full_name, ethnicity_mstr, CD_HISPANIC, mdm_race_cd,
                    src_race_ind_list, DT_LAST_UPDATE, language_mstr, std_suffix)
        -- Rtr_Exception.Valid_Party -> Write_C_S_FSS_PTY_RLE
        WHEN uq_rle THEN
            INTO C_S_FSS_PTY_RLE
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
            VALUES (rle_pkey, DT_LAST_UPDATE, version_seq, run_ts, DT_LAST_UPDATE, rle_pkey, hub_state_ind, pkey_trim,
                    rle_bo_class_cd, DT_LAST_UPDATE)
        -- Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN grp_gender AND uq_gender THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME)
            VALUES (src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
                    CD_GENDER, mapping_name, PTY_SRC_KEY, ID_CLIENT, CD_GENDER, DT_DOB, run_ts, NM_FIRST, NM_MIDDLE,
                    NM_LAST)
        -- Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
        WHEN grp_birth AND uq_birth THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES (src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
                    run_ts, mapping_name, CD_GENDER, attr_birth, ID_CLIENT, std_prfx_name, NM_FIRST, NM_LAST,
                    NM_MIDDLE, dob_text, DT_DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
        WHEN grp_ethnicity AND uq_ethnicity THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    attr_ethnicity, CD_GENDER, PTY_SRC_KEY, src_sys, NM_FIRST, std_lst_name, std_mdl_name,
                    mapping_name, DT_DOB, DT_LAST_UPDATE, ID_CLIENT, CD_HISPANIC)
        -- Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
        WHEN grp_race AND uq_race THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (ID_CLIENT, PTY_SRC_KEY, src_sys, race_exception_cd, race_exception_desc, race_exception_type,
                    run_ts, NM_FIRST, std_mdl_name, std_lst_name, CD_GENDER, DT_DOB, attr_race, std_prfx_name,
                    DT_LAST_UPDATE, mapping_name, src_race_ind_list)
        -- Rtr_Exception.Invalid_Language -> Write_Invalid_Party_Language
        WHEN grp_language AND uq_language THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, PERIOD_START_DATE)
            VALUES (src_sys, PTY_SRC_KEY, ID_CLIENT, language_exception_type, language_exception_code,
                    language_exception_desc, run_ts, NM_FIRST, std_mdl_name, std_lst_name, std_birth_date,
                    CD_GENDER, attr_language, LANGUAGE_CD, mapping_name, DT_LAST_UPDATE)
        -- Rtr_Exception.Invalid_Suffix -> Exp_Invalid_Suffix -> Write_Invalid_Party_Suffix
        WHEN grp_suffix AND uq_suffix THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, ALIAS_SUFFIX, BIRTH_DATE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, MAPPING_NAME)
            VALUES (src_sys, PTY_SRC_KEY, ID_CLIENT, suffix_exception_type, suffix_exception_code,
                    suffix_exception_desc, run_ts, NM_FIRST, NM_MIDDLE, NM_LAST, CD_SUFFIX, std_suffix, DT_DOB,
                    attr_suffix, CD_SUFFIX, mapping_name)
    SELECT *
      FROM (
        WITH
        lkp_cv    AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_cv_any AS (SELECT * FROM TABLE(fn_snow_helper42_common())),
        lkp_junk  AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc   AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
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
        -- mapplets, step 1: lookups and rule functions
        dq AS (
            SELECT a.*,
                   fn_snow_helper15_common(a.NM_FIRST, a.NM_MIDDLE, a.NM_LAST,
                       TRIM(NVL(a.NM_FIRST, '') || IFF(a.NM_MIDDLE IS NOT NULL, ' ' || TRIM(a.NM_MIDDLE), '')
                            || ' ' || NVL(LTRIM(a.NM_LAST), '')),
                       NULL, a.CD_SUFFIX, NULL, nsx.MSTR_CODE_VALUE,
                       jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)                                    AS nm,
                   fn_snow_helper17_common(a.CD_GENDER, 'Indv', 'FSS')                              AS gd,
                   /* VALIDATION */ fn_snow_helper16_common(a.DT_DOB, 'Indv', 'FSS', :l_run_ts)     AS birth_exception_code,
                   et.MSTR_CODE_VALUE                                                               AS ethnicity_mstr,
                   fn_snow_helper19_common(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
                   lg.MSTR_CODE_VALUE                                                               AS language_mstr,
                   sx.MSTR_CODE_VALUE                                                               AS std_suffix,
                   /* VALIDATION */ fn_snow_helper20_common(a.CD_SUFFIX, sx.MSTR_CODE_VALUE)       AS suffix_exception_code
              FROM active a
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.NM_FIRST)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.NM_LAST)) AND jl.IS_LAST_JUNK
              -- lkp_V_Lookup_Sfx_Code_Value inside the name mapplet (CODE_TYPE 'SUFFIX')
              LEFT JOIN lkp_cv nsx ON nsx.CODE_TYPE = 'SUFFIX' AND nsx.SRC_SYS = 'FSS' AND nsx.SRC_CODE_VALUE = a.CD_SUFFIX
              LEFT JOIN lkp_cv et  ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'FSS' AND et.SRC_CODE_VALUE = a.CD_HISPANIC
              LEFT JOIN lkp_cv lg  ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = 'FSS' AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD
              -- rule_Suffix_Std's lkp_V_LOOKUP_CODE_VALUE (no code-type filter)
              LEFT JOIN lkp_cv_any sx ON sx.SRC_SYS = 'FSS' AND sx.SRC_CODE_VALUE = a.CD_SUFFIX
        ),
        -- mapplets, step 2: exception catalogue
        dq2 AS (
            SELECT d.*,
                   d.nm:first_name::VARCHAR                       AS std_first_name,
                   d.nm:middle_name::VARCHAR                      AS std_mdl_name,
                   d.nm:last_name::VARCHAR                        AS std_lst_name,
                   d.nm:full_name::VARCHAR                        AS std_full_name,
                   d.nm:src_full_name::VARCHAR                    AS std_src_full_name,
                   d.nm:prfx_name::VARCHAR                        AS std_prfx_name,
                   d.gd:mdm_gender_code::VARCHAR                  AS mdm_gender_code,
                   d.gd:exception_code::VARCHAR                   AS gender_exception_code,
                   xg.EXCEPTION_DESC                              AS gender_exception_description,
                   xg.EXCEPTION_TYPE                              AS gender_exception_type,
                   /* BAD DATA */ IFF(d.birth_exception_code IS NULL, d.DT_DOB, NULL) AS std_birth_date,
                   xb.EXCEPTION_DESC                              AS birth_exception_description,
                   xb.EXCEPTION_TYPE                              AS birth_exception_type,
                   xe.EXCEPTION_CODE                              AS ethnicity_exception_code,
                   xe.EXCEPTION_DESC                              AS ethnicity_exception_desc,
                   xe.EXCEPTION_TYPE                              AS ethnicity_exception_type,
                   d.rc:mdm_race_cd::VARCHAR                      AS mdm_race_cd,
                   d.rc:src_race_ind_list::VARCHAR                AS src_race_ind_list,
                   xr.EXCEPTION_CODE                              AS race_exception_cd,
                   xr.EXCEPTION_DESC                              AS race_exception_desc,
                   xr.EXCEPTION_TYPE                              AS race_exception_type,
                   xl.EXCEPTION_CODE                              AS language_exception_code,
                   xl.EXCEPTION_DESC                              AS language_exception_desc,
                   xl.EXCEPTION_TYPE                              AS language_exception_type,
                   xs.EXCEPTION_DESC                              AS suffix_exception_desc,
                   xs.EXCEPTION_TYPE                              AS suffix_exception_type
              FROM dq d
              LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
              LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
              LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = d.rc:exception_code::VARCHAR
              LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language')
              LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.suffix_exception_code
        ),
        routed AS (
            SELECT d.*,
                   TRIM(d.PTY_SRC_KEY)                                                   AS pkey_trim,
                   TRIM(d.PTY_SRC_KEY) || '|' || :P_RLE_BO_CLASS_CD_MEMBER                AS rle_pkey,
                   (d.gender_exception_description IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT') AS grp_gender,
                   d.birth_exception_code IS NOT NULL                                    AS grp_birth,
                   (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT')  AS grp_ethnicity,
                   (d.race_exception_desc IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT')       AS grp_race,
                   d.language_exception_code IS NOT NULL                                 AS grp_language,
                   d.suffix_exception_code IS NOT NULL                                   AS grp_suffix
              FROM dq2 d
        )
        SELECT r.*,
               1 /* TIMELINE: VERSION_SEQ hard-coded */                  AS version_seq,
               1                                                          AS hub_state_ind,
               'FSS'                                                      AS src_sys,
               :l_run_ts                                                  AS run_ts,
               :c_mapping                                                 AS mapping_name,
               :P_PTY_BO_CLASS_CD_MEMBER                                  AS pty_bo_class_cd,
               :P_RLE_BO_CLASS_CD_MEMBER                                  AS rle_bo_class_cd,
               TO_VARCHAR(r.DT_DOB, 'MM/DD/YYYY')                         AS dob_text,
               'Gender'                                                   AS attr_gender,
               'Birth Date'                                               AS attr_birth,
               'Ethnicity_Cd'                                             AS attr_ethnicity,
               'Race_Cd'                                                  AS attr_race,
               'Language_Cd'                                              AS attr_language,
               'Name Suffix'                                              AS attr_suffix,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1
                AND xp.PKEY_SRC_OBJECT IS NULL)                           AS uq_pty,
               (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1
                AND xr2.PKEY_SRC_OBJECT IS NULL)                          AS uq_rle,
               ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.ID_CLIENT, r.gender_exception_type,
                                               r.gender_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_gender,
               ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.ID_CLIENT, r.birth_exception_type,
                                               r.birth_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1  AS uq_birth,
               ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.ID_CLIENT,
                                               r.ethnicity_exception_type, r.ethnicity_exception_code
                                      ORDER BY r.DT_LAST_UPDATE DESC) = 1                                  AS uq_ethnicity,
               ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.ID_CLIENT, r.race_exception_type,
                                               r.race_exception_cd ORDER BY r.DT_LAST_UPDATE DESC) = 1     AS uq_race,
               ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.PTY_SRC_KEY, r.ID_CLIENT,
                                               r.language_exception_type, r.language_exception_code
                                      ORDER BY r.DT_LAST_UPDATE DESC) = 1                                  AS uq_language,
               ROW_NUMBER() OVER (PARTITION BY r.grp_suffix, r.PTY_SRC_KEY, r.ID_CLIENT, r.suffix_exception_type,
                                               r.suffix_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 AS uq_suffix
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY WHERE VERSION_SEQ = 1) xp
                 ON xp.PKEY_SRC_OBJECT = r.pkey_trim
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE WHERE VERSION_SEQ = 1) xr2
                 ON xr2.PKEY_SRC_OBJECT = r.rle_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_FSS_PTY, C_S_FSS_PTY_RLE, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
