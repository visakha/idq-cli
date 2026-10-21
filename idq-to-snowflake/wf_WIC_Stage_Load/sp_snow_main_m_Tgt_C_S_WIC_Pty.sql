--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_WIC_Pty
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty (workflow wf_WIC_Stage_Load).
--
-- Loads the WIC parties (V_WIC_ETL_SRC) into C_S_WIC_PTY and C_S_WIC_PTY_RLE (insert only, never truncated) and logs
-- demographic exceptions:
--   -> Flt_Remove_Inactive: party not in STG_WIC_PTY_INACTIVE_STS
--   -> name standardization, gender, birth date, ethnicity, race indicators, language
--   -> Rtr_Exception: Valid_Party is TRUE (every active party loaded); each failed rule writes an
--      EXC_STG_BAD_REC_MEMB row - gender, ethnicity and race only for SOURCE_TABLE = 'CLIENT', birth date and
--      language for every row.
--
-- VALIDATION: fn_snow_helper15_common (name), fn_snow_helper17_common (gender), fn_snow_helper16_common (birth date),
--   fn_snow_helper18_common with V_LOOKUP_CODE_VALUE ETHNICITY / LANGUAGE_CD, fn_snow_helper19_common (race
--   indicators).
-- BAD DATA: an exception never rejects the party (loaded AND logged). C_S_WIC_PTY.BIRTH_DT is the source DOB (IDQ
--   links the source port); the language exception row writes the mapplet's birth date (NULL for a future one).
--   Birth weight in grams is BIRTH_WT_OZ * 28.35 (ounces only, the deliberate 3/14/2025 change). Unique keys
--   Snowflake does not enforce are applied: C_S_WIC_PTY, C_S_WIC_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ) and
--   EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM); PERIOD_START_DATE = DATEKEY.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_WIC_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_WIC_Pty';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP() / SYSDATE
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_WIC_PTY, C_S_WIC_PTY_RLE. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_WIC_PTY
        WHEN uq_pty THEN
            INTO C_S_WIC_PTY
                 (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND, PTY_BO_CLASS_CD,
                  BIRTH_WGHT_GRMS, PERIOD_START_DATE, CREATE_DATE, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD,
                  BIRTH_DT, SRC_RACE_CD, RACE_CD, ETHNCTY, SRC_ETHNCTY, PRFRD_LANG_CD, SRC_LAST_UPD_DT,
                  SRC_PRFRD_LANG_CD, SRC_FULL_NM)
            VALUES (pkey_trim, version_seq, run_ts, pkey_trim, hub_state_ind, pty_bo_class_cd, birth_wght_grms,
                    DATEKEY, DATEKEY, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name,
                    mdm_gender_code, DOB, src_race_ind_list, mdm_race_cd, ethnicity_mstr, ETHNICITY, language_mstr,
                    DATEKEY, LANGUAGE_CD, std_src_full_name)
        -- Rtr_Exception.Valid_Party -> Write_C_S_WIC_PTY_RLE
        WHEN uq_rle THEN
            INTO C_S_WIC_PTY_RLE
                 (PKEY_SRC_OBJECT, SRC_ROWID, RLE_BO_CLASS_CD, PTY_FK, VERSION_SEQ, LAST_UPDATE_DATE, HUB_STATE_IND,
                  CREATE_DATE, PERIOD_START_DATE, SRC_LAST_UPD_DT)
            VALUES (rle_pkey, rle_pkey, rle_bo_class_cd, pkey_trim, version_seq, run_ts, hub_state_ind, DATEKEY,
                    DATEKEY, DATEKEY)
        -- Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN grp_gender AND uq_gender THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME)
            VALUES (src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
                    GENDER, mapping_name, PTY_SRC_KEY, ID, GENDER, DOB, run_ts, FIRST_NAME, MIDDLE_NAME, LAST_NAME)
        -- Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
        WHEN grp_birth AND uq_birth THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES (src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
                    run_ts, mapping_name, GENDER, attr_birth, ID, std_prfx_name, FIRST_NAME, LAST_NAME, MIDDLE_NAME,
                    dob_text, DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
        WHEN grp_ethnicity AND uq_ethnicity THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    attr_ethnicity, GENDER, PTY_SRC_KEY, src_sys, FIRST_NAME, std_lst_name, std_mdl_name,
                    mapping_name, DOB, DATEKEY, ID, ETHNICITY)
        -- Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
        WHEN grp_race AND uq_race THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (ID, PTY_SRC_KEY, src_sys, race_exception_cd, race_exception_desc, race_exception_type, run_ts,
                    FIRST_NAME, std_mdl_name, std_lst_name, GENDER, DOB, attr_race, std_prfx_name, DATEKEY,
                    mapping_name, src_race_ind_list)
        -- Rtr_Exception.Invalid_Language -> Write_Invalid_Party_Language
        WHEN grp_language AND uq_language THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, PERIOD_START_DATE)
            VALUES (src_sys, PTY_SRC_KEY, ID, language_exception_type, language_exception_code,
                    language_exception_desc, run_ts, FIRST_NAME, std_mdl_name, std_lst_name, std_birth_date,
                    GENDER, attr_language, LANGUAGE_CD, mapping_name, DATEKEY)
    SELECT *
      FROM (
        WITH
        lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_V_WIC_ETL_SRC + Lookup_STG_WIC_PTY_INACTIVE_STS + Flt_Remove_Inactive
        active AS (
            SELECT v.SOURCE_TABLE, v.DATEKEY, v.LOAD_DATE, v.ID, v.PTY_SRC_KEY, v.FIRST_NAME, v.LAST_NAME,
                   v.MIDDLE_NAME, v.DOB, v.GENDER, v.BIRTH_WT_LB, v.BIRTH_WT_OZ, v.LANGUAGE_CD, v.ETHNICITY,
                   v.RACE_WHITE_IND, v.RACE_AA_IND, v.RACE_ASIAN_IND, v.RACE_PI_IND, v.RACE_AN_IND
              FROM V_WIC_ETL_SRC v
             WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'WIC'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        dq AS (
            SELECT a.*,
                   fn_snow_helper15_common(a.FIRST_NAME, a.MIDDLE_NAME, a.LAST_NAME,
                       TRIM(NVL(a.FIRST_NAME, '') || IFF(a.MIDDLE_NAME IS NOT NULL, ' ' || TRIM(a.MIDDLE_NAME), '')
                            || ' ' || NVL(LTRIM(a.LAST_NAME), '')),
                       NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)        AS nm,
                   fn_snow_helper17_common(a.GENDER, 'Indv', 'WIC')                            AS gd,
                   /* VALIDATION */ fn_snow_helper16_common(a.DOB, 'Indv', 'WIC', :l_run_ts)  AS birth_exception_code,
                   et.MSTR_CODE_VALUE                                                          AS ethnicity_mstr,
                   fn_snow_helper19_common(a.RACE_WHITE_IND, a.RACE_AA_IND, a.RACE_ASIAN_IND, a.RACE_PI_IND,
                                           a.RACE_AN_IND)                                      AS rc,
                   lg.MSTR_CODE_VALUE                                                          AS language_mstr
              FROM active a
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRST_NAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LAST_NAME)) AND jl.IS_LAST_JUNK
              LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'WIC' AND et.SRC_CODE_VALUE = a.ETHNICITY
              LEFT JOIN lkp_cv lg ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = 'WIC' AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD
        ),
        dq2 AS (
            SELECT d.*,
                   d.nm:first_name::VARCHAR          AS std_first_name,
                   d.nm:middle_name::VARCHAR         AS std_mdl_name,
                   d.nm:last_name::VARCHAR           AS std_lst_name,
                   d.nm:full_name::VARCHAR           AS std_full_name,
                   d.nm:src_full_name::VARCHAR       AS std_src_full_name,
                   d.nm:prfx_name::VARCHAR           AS std_prfx_name,
                   d.gd:mdm_gender_code::VARCHAR     AS mdm_gender_code,
                   d.gd:exception_code::VARCHAR      AS gender_exception_code,
                   xg.EXCEPTION_DESC                 AS gender_exception_description,
                   xg.EXCEPTION_TYPE                 AS gender_exception_type,
                   /* BAD DATA */ IFF(d.birth_exception_code IS NULL, d.DOB, NULL) AS std_birth_date,
                   xb.EXCEPTION_DESC                 AS birth_exception_description,
                   xb.EXCEPTION_TYPE                 AS birth_exception_type,
                   xe.EXCEPTION_CODE                 AS ethnicity_exception_code,
                   xe.EXCEPTION_DESC                 AS ethnicity_exception_desc,
                   xe.EXCEPTION_TYPE                 AS ethnicity_exception_type,
                   d.rc:mdm_race_cd::VARCHAR         AS mdm_race_cd,
                   d.rc:src_race_ind_list::VARCHAR   AS src_race_ind_list,
                   xr.EXCEPTION_CODE                 AS race_exception_cd,
                   xr.EXCEPTION_DESC                 AS race_exception_desc,
                   xr.EXCEPTION_TYPE                 AS race_exception_type,
                   xl.EXCEPTION_CODE                 AS language_exception_code,
                   xl.EXCEPTION_DESC                 AS language_exception_desc,
                   xl.EXCEPTION_TYPE                 AS language_exception_type
              FROM dq d
              LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
              LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
              LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = d.rc:exception_code::VARCHAR
              LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language')
        ),
        routed AS (
            SELECT d.*,
                   TRIM(d.PTY_SRC_KEY)                                                    AS pkey_trim,
                   TRIM(d.PTY_SRC_KEY) || '|' || :P_RLE_BO_CLASS_CD_MEMBER                 AS rle_pkey,
                   (d.gender_exception_description IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT') AS grp_gender,
                   d.birth_exception_code IS NOT NULL                                     AS grp_birth,
                   (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT')  AS grp_ethnicity,
                   (d.race_exception_desc IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT')       AS grp_race,
                   d.language_exception_code IS NOT NULL                                  AS grp_language
              FROM dq2 d
        )
        SELECT r.*,
               1 /* TIMELINE: VERSION_SEQ hard-coded */         AS version_seq,
               1                                                 AS hub_state_ind,
               'WIC'                                             AS src_sys,
               :l_run_ts                                         AS run_ts,
               :c_mapping                                        AS mapping_name,
               :P_PTY_BO_CLASS_CD_MEMBER                         AS pty_bo_class_cd,
               :P_RLE_BO_CLASS_CD_MEMBER                         AS rle_bo_class_cd,
               r.BIRTH_WT_OZ * 28.35                             AS birth_wght_grms,
               TO_VARCHAR(r.DOB, 'MM/DD/YYYY')                   AS dob_text,
               'Gender'                                          AS attr_gender,
               'Birth Date'                                      AS attr_birth,
               'Ethnicity_Cd'                                    AS attr_ethnicity,
               'Race_Cd'                                         AS attr_race,
               'Language_Cd'                                     AS attr_language,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DATEKEY DESC, r.ID) = 1
                AND xp.PKEY_SRC_OBJECT IS NULL)                  AS uq_pty,
               (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DATEKEY DESC, r.ID) = 1
                AND xr2.PKEY_SRC_OBJECT IS NULL)                 AS uq_rle,
               ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.ID, r.gender_exception_type,
                                               r.gender_exception_code ORDER BY r.DATEKEY DESC) = 1   AS uq_gender,
               ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.ID, r.birth_exception_type,
                                               r.birth_exception_code ORDER BY r.DATEKEY DESC) = 1    AS uq_birth,
               ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.ID, r.ethnicity_exception_type,
                                               r.ethnicity_exception_code ORDER BY r.DATEKEY DESC) = 1 AS uq_ethnicity,
               ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.ID, r.race_exception_type,
                                               r.race_exception_cd ORDER BY r.DATEKEY DESC) = 1       AS uq_race,
               ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.PTY_SRC_KEY, r.ID, r.language_exception_type,
                                               r.language_exception_code ORDER BY r.DATEKEY DESC) = 1 AS uq_language
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY WHERE VERSION_SEQ = 1) xp
                 ON xp.PKEY_SRC_OBJECT = r.pkey_trim
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE WHERE VERSION_SEQ = 1) xr2
                 ON xr2.PKEY_SRC_OBJECT = r.rle_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_WIC_PTY, C_S_WIC_PTY_RLE, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
