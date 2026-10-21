--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TTF_Pty
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty (workflow wf_TTF_Stage_Load).
--
-- Loads the TTF clients (V_TTF_ETL_SRC) into C_S_TTF_PTY and C_S_TTF_PTY_RLE (insert only, never truncated) and logs
-- demographic exceptions:
--   -> Flt_Remove_Inactive: party (PTY_SRC_KEY) not in STG_TTF_PTY_INACTIVE_STS
--   -> Expression: gender from SEXID (33 -> F, 34 -> M, else U); ethnicity = '55' when RACEETHNICITYID = '55'
--   -> name standardization (TTF CopyOf_ mapplet), gender, birth date, ethnicity, race by code (mplt_Race_Validation
--      on RACEETHNICITYID)
--   -> Rtr_Exception: Valid_Party is TRUE (every active client loaded); birth date, gender, ethnicity and race
--      failures each write an EXC_STG_BAD_REC_MEMB row for every row (no source-table condition in TTF).
--
-- VALIDATION: fn_snow_helper15_common (name), fn_snow_helper17_common (gender, routed on the looked-up description),
--   fn_snow_helper16_common (birth date), fn_snow_helper18_common with V_LOOKUP_CODE_VALUE ETHNICITY / RACE
--   (routed on the looked-up code). The Invalid_Language / Invalid_Suffix router groups test ports that are not fed
--   in IDQ and have no target, so they never write (docs/common_insights.md 1.4): not generated.
-- BAD DATA: an exception never rejects the client (loaded AND logged); a future birth date is loaded as NULL.
--   PRFRD_LANG_CD and SFX_NM are linked to unfed ports in IDQ (NULL). Unique keys Snowflake does not enforce are
--   applied: C_S_TTF_PTY, C_S_TTF_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
-- TIMELINE: VERSION_SEQ hard-coded to 1; party PERIOD_START_DATE = run start ($sys.MappingRunStartTime, so it
--   changes on every run: docs/common_insights.md 1.11), role PERIOD_START_DATE = SUBMITDATE.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TTF_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TTF_Pty';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSDATE
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TTF_PTY, C_S_TTF_PTY_RLE. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_TTF_PTY
        WHEN uq_pty THEN
            INTO C_S_TTF_PTY
                 (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, HUB_STATE_IND,
                  PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, SRC_FULL_NM, ETHNCTY,
                  SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM, PERIOD_START_DATE,
                  BIRTH_DT)
            VALUES (pkey_trim, version_seq, run_ts, SUBMITDATE, pkey_trim, hub_state_ind, pty_bo_class_cd,
                    std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name, mdm_gender_code,
                    std_src_full_name, ethnicity_mstr, ethnicity, race_mstr, RACEETHNICITYID, SUBMITDATE, NULL, NULL,
                    run_ts, std_birth_date)
        -- Rtr_Exception.Valid_Party -> Write_C_S_TTF_PTY_RLE
        WHEN uq_rle THEN
            INTO C_S_TTF_PTY_RLE
                 (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
                  HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
            VALUES (rle_pkey, SUBMITDATE, version_seq, run_ts, SUBMITDATE, rle_pkey, hub_state_ind, pkey_trim,
                    rle_bo_class_cd, SUBMITDATE)
        -- Rtr_Exception.Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN grp_gender AND uq_gender THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME)
            VALUES (src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
                    gender, mapping_name, PTY_SRC_KEY, CLIENTS_ID, gender, DOB, run_ts, FIRSTNAME, MIDDLENAME,
                    LASTNAME)
        -- Rtr_Exception.Invalid_Birth_Date -> Write_Invalid_Party_DOB
        WHEN grp_birth AND uq_birth THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES (src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
                    run_ts, mapping_name, gender, attr_birth, CLIENTS_ID, std_prfx_name, FIRSTNAME, LASTNAME,
                    MIDDLENAME, dob_text, DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Write_Invalid_Party_Ethnicity
        WHEN grp_ethnicity AND uq_ethnicity THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    attr_ethnicity, gender, PTY_SRC_KEY, src_sys, FIRSTNAME, std_lst_name, std_mdl_name,
                    mapping_name, DOB, SUBMITDATE, CLIENTS_ID, ethnicity)
        -- Rtr_Exception.Invalid_Race -> Write_Invalid_Party_Race
        WHEN grp_race AND uq_race THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (CLIENTS_ID, PTY_SRC_KEY, src_sys, race_exception_code, race_exception_desc, race_exception_type,
                    run_ts, FIRSTNAME, std_mdl_name, std_lst_name, gender, DOB, attr_race, std_prfx_name, SUBMITDATE,
                    mapping_name, RACEETHNICITYID)
    SELECT *
      FROM (
        WITH
        lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_V_TTF_ETL_SRC + Expression + Lookup_STG_TTF_PTY_INACTIVE_STS + Flt_Remove_Inactive
        active AS (
            SELECT v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.SUBMITDATE, v.SEXID,
                   v.RACEETHNICITYID, v.PTY_SRC_KEY, v.LOAD_DATE,
                   DECODE(v.SEXID, '33', 'F', '34', 'M', 'U')            AS gender,
                   IFF(v.RACEETHNICITYID = '55', '55', NULL)             AS ethnicity
              FROM V_TTF_ETL_SRC v
             WHERE NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i
                                WHERE i.SRC_KEY = v.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'TTF'
                                  AND i.DEACTIVATION_STS IS NOT NULL)
        ),
        dq AS (
            SELECT a.*,
                   fn_snow_helper15_common(a.FIRSTNAME, a.MIDDLENAME, a.LASTNAME,
                       TRIM(NVL(a.FIRSTNAME, '') || IFF(a.MIDDLENAME IS NOT NULL, ' ' || TRIM(a.MIDDLENAME), '')
                            || ' ' || NVL(LTRIM(a.LASTNAME), '')),
                       NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)        AS nm,
                   fn_snow_helper17_common(a.gender, 'Indv', 'TTF')                            AS gd,
                   /* VALIDATION */ fn_snow_helper16_common(a.DOB, 'Indv', 'TTF', :l_run_ts)  AS birth_exception_code,
                   et.MSTR_CODE_VALUE                                                          AS ethnicity_mstr,
                   rc.MSTR_CODE_VALUE                                                          AS race_mstr
              FROM active a
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRSTNAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LASTNAME)) AND jl.IS_LAST_JUNK
              LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'TTF' AND et.SRC_CODE_VALUE = a.ethnicity
              LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'TTF' AND rc.SRC_CODE_VALUE = a.RACEETHNICITYID
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
                   xr.EXCEPTION_CODE                 AS race_exception_code,
                   xr.EXCEPTION_DESC                 AS race_exception_desc,
                   xr.EXCEPTION_TYPE                 AS race_exception_type
              FROM dq d
              LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
              LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
              LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
        ),
        routed AS (
            SELECT d.*,
                   TRIM(d.PTY_SRC_KEY)                                        AS pkey_trim,
                   TRIM(d.PTY_SRC_KEY) || '|' || :P_RLE_BO_CLASS_CD_MEMBER     AS rle_pkey,
                   d.gender_exception_description IS NOT NULL                 AS grp_gender,
                   d.birth_exception_code IS NOT NULL                         AS grp_birth,
                   d.ethnicity_exception_code IS NOT NULL                     AS grp_ethnicity,
                   d.race_exception_desc IS NOT NULL                          AS grp_race
              FROM dq2 d
        )
        SELECT r.*,
               1 /* TIMELINE: VERSION_SEQ hard-coded */         AS version_seq,
               1                                                 AS hub_state_ind,
               'TTF'                                             AS src_sys,
               :l_run_ts                                         AS run_ts,
               :c_mapping                                        AS mapping_name,
               :P_PTY_BO_CLASS_CD_MEMBER                         AS pty_bo_class_cd,
               :P_RLE_BO_CLASS_CD_MEMBER                         AS rle_bo_class_cd,
               TO_VARCHAR(r.DOB, 'MM/DD/YYYY')                   AS dob_text,
               'Gender'                                          AS attr_gender,
               'Birth Date'                                      AS attr_birth,
               'Ethnicity_Cd'                                    AS attr_ethnicity,
               'Race_Cd'                                         AS attr_race,
               /* BAD DATA: unique keys Snowflake does not enforce */
               (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1
                AND xp.PKEY_SRC_OBJECT IS NULL)                  AS uq_pty,
               (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1
                AND xr2.PKEY_SRC_OBJECT IS NULL)                 AS uq_rle,
               ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.CLIENTS_ID, r.gender_exception_type,
                                               r.gender_exception_code ORDER BY r.SUBMITDATE DESC) = 1 AS uq_gender,
               ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.CLIENTS_ID, r.birth_exception_type,
                                               r.birth_exception_code ORDER BY r.SUBMITDATE DESC) = 1  AS uq_birth,
               ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.CLIENTS_ID,
                                               r.ethnicity_exception_type, r.ethnicity_exception_code
                                      ORDER BY r.SUBMITDATE DESC) = 1                                  AS uq_ethnicity,
               ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.CLIENTS_ID, r.race_exception_type,
                                               r.race_exception_code ORDER BY r.SUBMITDATE DESC) = 1   AS uq_race
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY WHERE VERSION_SEQ = 1) xp
                 ON xp.PKEY_SRC_OBJECT = r.pkey_trim
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE WHERE VERSION_SEQ = 1) xr2
                 ON xr2.PKEY_SRC_OBJECT = r.rle_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_TTF_PTY, C_S_TTF_PTY_RLE, exceptions)', :l_rows)
      INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
