--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_ECI_Pty
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty (workflow wf_ECI_Stage_Load).
--
-- Loads the ECI child and family parties of the delta into C_S_ECI_PTY and C_S_ECI_PTY_RLE (insert only, never
-- truncated) and logs demographic exceptions:
--   Read_STG_ECI_D_CHILD_AND_FAMILY (custom SQL)
--     -> Flt_Remove_Inactive: IsNull(DEACTIVATION_STS) on STG_ECI_PTY_INACTIVE_STS (the stored condition is
--        "--not IsNull(...)"; "--not" is an IDQ comment, so ACTIVE parties are kept)
--     -> name standardization, gender, birth date, ethnicity, race indicators, language
--     -> Rtr_Exception: Valid_Party is TRUE, so every active party is loaded; each failed rule additionally writes
--        one EXC_STG_BAD_REC_MEMB row (ethnicity, race and language only for child rows).
-- The source read also stores a filter on five child ids; it is not part of the custom query and is ignored, as in
-- IDQ (custom query mode).
--
-- VALIDATION (mapplets written out in common/01_snow_common_functions.sql):
--   mplt_Name_Standardization_Indv_Member  fn_snow_helper15_common (+ REF_JUNK_NAME_LIST lookup)
--   mplt_Gender_Validation                 fn_snow_helper17_common   -> Invalid_Gender (routed on the looked-up
--                                                                       description: unconfigured code = no row)
--   mplt_BirthDate_Validation              fn_snow_helper16_common   -> Invalid_Birth_Date (birth date then NULL)
--   mplt_Ethnicity_Validation              fn_snow_helper18_common + V_LOOKUP_CODE_VALUE ETHNICITY
--   mplt_Race_Ind_Validation               fn_snow_helper19_common   -> Invalid_Race
--   mplt_Language_Validation               fn_snow_helper18_common + V_LOOKUP_CODE_VALUE LANGUAGE_CD
--   Ethnicity, race and language exceptions write the code as RETURNED by the EXC_LOOKUP_CODE_VALUE lookup and are
--   routed on it (or on its description), so an exception that is not configured writes no row.
-- BAD DATA: an exception never rejects the party (Valid_Party = TRUE): the party is loaded AND logged. A future
--   birth date is loaded as NULL. Exception rows carry MAPPING_NAME 'm_Tgt_C_S_ECI_Pty_OnGoing' (literal in the
--   IDQ expressions). Unique keys that Snowflake does not enforce are applied here: C_S_ECI_PTY and C_S_ECI_PTY_RLE
--   (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB (SRC_SYS, SRC_SYS_ID_1..3, EXCEPTION_TYPE,
--   EXCEPTION_CODE, RUN_DATE): a row whose key is already in the table, or already written in this run, is not
--   written (IDQ rejects it and carries on).
-- TIMELINE (stale MDM timeline, ported here as IDQ does it):
--   * VERSION_SEQ is hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM = 1) on both targets.
--   * exp_Party_Consolidation also computes DUP_RANK and an MD5 of the demographics for the timeline; neither is
--     written by IDQ, so they are not computed here.
--   * PERIOD_START_DATE: party = source DATE_MODIFIED (DATE_MODIFIED, else DATE_CREATED); role = DATE_CREATED.
--
-- Target load order (IDQ): Write_Invalid_Party_Ethnicity before Write_Invalid_Party_Race; the INTO clauses keep that
-- order.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',     -- $PTY_BO_CLASS_CD_Member
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member'    -- $RLE_BO_CLASS_CD_Member
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping      VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty';
    c_exc_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_ECI_Pty_OnGoing';
    l_run_ts       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- SYSTIMESTAMP() / SYSDATE
    l_rows         NUMBER DEFAULT 0;
    l_line         VARCHAR;
    l_log          VARCHAR DEFAULT '';
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_ECI_PTY, C_S_ECI_PTY_RLE. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- Rtr_Exception.Valid_Party (TRUE) -> exp_Party_Consolidation -> Write_C_S_ECI_PTY
        WHEN uq_pty THEN
            INTO C_S_ECI_PTY
                 (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
                  PTY_BO_CLASS_CD, PRFX_NM, FULL_NM, LST_NM, MDL_NM, FRST_NM, GNDR_CD, BIRTH_DT, SRC_FULL_NM,
                  SRC_LAST_UPD_DT, BIRTH_WGHT_GRMS, HUB_STATE_IND, SRC_ETHNCTY, ETHNCTY, RACE_CD, PRFRD_LANG_CD,
                  SRC_PRFRD_LANG_CD, SRC_RACE_CD, PERIOD_START_DATE)
            VALUES (pkey_trim, version_seq, run_ts, MODIFIED_BY, DATE_CREATED, CREATED_BY, pkey_trim,
                    pty_bo_class_cd, std_prfx_name, std_full_name, std_lst_name, std_mdl_name, std_first_name,
                    mdm_gender_code, std_birth_date, std_src_full_name, DATE_MODIFIED, birth_wght_grms,
                    hub_state_ind, ETHNICITY, ethnicity_mstr, mdm_race_cd, language_mstr, LANGUAGE_CD,
                    src_race_ind_list, DATE_MODIFIED)
        -- Rtr_Exception.Valid_Party -> Write_C_S_ECI_PTY_RLE
        WHEN uq_rle THEN
            INTO C_S_ECI_PTY_RLE
                 (PKEY_SRC_OBJECT, LAST_UPDATE_DATE, CREATOR, CREATE_DATE, VERSION_SEQ, PTY_FK, SRC_LAST_UPD_DT,
                  RLE_BO_CLASS_CD, PERIOD_START_DATE, HUB_STATE_IND, SRC_ROWID)
            VALUES (rle_pkey, run_ts, CREATED_BY, DATE_CREATED, version_seq, pkey_trim, DATE_MODIFIED,
                    rle_bo_class_cd, DATE_CREATED, hub_state_ind, rle_pkey)
        -- Rtr_Exception.Invalid_Gender_Code -> Exp_Invalid_Gender -> Write_Invalid_Party_Gender
        WHEN grp_gender AND uq_gender THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE)
            VALUES (src_system, gender_exception_type, gender_exception_code, gender_exception_description,
                    attr_gender, GENDER, exc_mapping, pkey_src_object, ID, GENDER, DOB, run_ts)
        -- Rtr_Exception.Invalid_Birth_Date -> Exp_Invalid_DOB -> Write_Invalid_Party_DOB
        WHEN grp_birth AND uq_birth THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
                  GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
                  BIRTH_DATE)
            VALUES (src_system, pkey_src_object, birth_exception_code, birth_exception_description,
                    birth_exception_type, run_ts, exc_mapping, GENDER, attr_birth, ID, std_prfx_name,
                    FIRST_NAME, LAST_NAME, MIDDLE_INITIAL, dob_text, DOB)
        -- Rtr_Exception.Invalid_Ethnicity -> Exp_Load_Ethnicity_Exceptions -> Write_Invalid_Party_Ethnicity
        WHEN grp_ethnicity AND uq_ethnicity THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
                  SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
                  SRC_SYS_ID_2, ATTRIBUTE_VALUE)
            VALUES (run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
                    attr_ethnicity, GENDER, pkey_src_object, src_system, FIRST_NAME, std_lst_name, std_mdl_name,
                    exc_mapping, DOB, DATE_CREATED, ID, ETHNICITY)
        -- Rtr_Exception.Invalid_Race -> Exp_Load_Race_Exceptions -> Write_Invalid_Party_Race
        WHEN grp_race AND uq_race THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS_ID_2, SRC_SYS_ID_1, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, GENDER, BIRTH_DATE, ATTRIBUTE_NAME, PREFIX, PERIOD_START_DATE,
                  MAPPING_NAME, ATTRIBUTE_VALUE)
            VALUES (ID, pkey_src_object, src_system, race_exception_cd, race_exception_desc, race_exception_type,
                    run_ts, FIRST_NAME, std_mdl_name, std_lst_name, GENDER, DOB, attr_race, std_prfx_name,
                    DATE_CREATED, exc_mapping, src_race_ind_list)
        -- Rtr_Exception.Invalid_Language -> Exp_Load_Language_Exceptions -> Write_Invalid_Party_Language
        WHEN grp_language AND uq_language THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
                  MAPPING_NAME, PERIOD_START_DATE)
            VALUES (src_system, pkey_src_object, ID, language_exception_type, language_exception_code,
                    language_exception_desc, run_ts, FIRST_NAME, std_mdl_name, std_lst_name, std_birth_date,
                    GENDER, attr_language, LANGUAGE_CD, exc_mapping, DATE_CREATED)
    SELECT *
      FROM (
        WITH
        lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_STG_ECI_D_CHILD_AND_FAMILY (custom SQL, query mode SEMI)
        src AS (
            SELECT 'ECI_CHILD' AS SOURCE_TABLE, child.ID_CHILD AS ID, child.CHILD_SSN, child.FIRST_NAME,
                   child.LAST_NAME, child.MIDDLE_INITIAL, child.DOB, child.GESTATION_AGE, child.GENDER,
                   child.BIRTH_WT_LB, child.BIRTH_WT_OZ, child.INTERPRET_IND, child.LANGUAGE_CD, child.RACE_CD,
                   child.DATE_CREATED, COALESCE(child.DATE_MODIFIED, child.DATE_CREATED) AS DATE_MODIFIED,
                   child.MODIFIED_BY, child.CREATED_BY, child.ETHNICITY, child.RACE_WHITE, child.RACE_AA,
                   child.RACE_ASIAN, child.RACE_PI, child.RACE_AN, child.LOAD_DATE
              FROM STG_ECI_D_CHILD child
            UNION ALL
            SELECT 'ECI_FAMILY', fam.ID_FAMILY, NULL, fam.FIRST_NAME, fam.LAST_NAME, fam.MIDDLE_INITIAL, fam.DOB,
                   NULL, fam.GENDER, NULL, NULL, NULL, NULL, NULL, fam.DATE_CREATED,
                   COALESCE(fam.DATE_MODIFIED, fam.DATE_CREATED), fam.MODIFIED_BY, fam.CREATED_BY, NULL, NULL,
                   NULL, NULL, NULL, NULL, fam.LOAD_DATE
              FROM STG_ECI_D_FAMILY fam
        ),
        -- Exp_ECI_Data_Load
        exp_load AS (
            SELECT s.*,
                   LPAD(TO_VARCHAR(s.ID), 10, '0') || IFF(s.SOURCE_TABLE = 'ECI_FAMILY', 'F', '')  AS pkey_src_object,
                   'Indv' AS party_type,
                   'ECI'  AS src_system,
                   TRIM(NVL(s.FIRST_NAME, '')
                        || IFF(s.MIDDLE_INITIAL IS NOT NULL, ' ' || TRIM(s.MIDDLE_INITIAL), '')
                        || ' ' || NVL(LTRIM(s.LAST_NAME), ''))                                      AS src_full_name
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
        -- mapplets, step 1: lookups and the rule functions
        dq AS (
            SELECT a.*,
                   fn_snow_helper15_common(a.FIRST_NAME, a.MIDDLE_INITIAL, a.LAST_NAME, a.src_full_name, NULL, NULL,
                                           NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)       AS nm,
                   fn_snow_helper17_common(a.GENDER, a.party_type, a.src_system)                       AS gd,
                   /* VALIDATION */ fn_snow_helper16_common(a.DOB, a.party_type, a.src_system, :l_run_ts) AS birth_exception_code,
                   et.MSTR_CODE_VALUE                                                                  AS ethnicity_mstr,
                   fn_snow_helper19_common(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
                   lg.MSTR_CODE_VALUE                                                                  AS language_mstr
              FROM active a
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRST_NAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LAST_NAME)) AND jl.IS_LAST_JUNK
              LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = a.src_system
                                 AND et.SRC_CODE_VALUE = a.ETHNICITY
              LEFT JOIN lkp_cv lg ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = a.src_system
                                 AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD
        ),
        -- mapplets, step 2: the exception catalogue (EXC_LOOKUP_CODE_VALUE) of every rule
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
                   /* BAD DATA */ IFF(d.birth_exception_code IS NULL, d.DOB, NULL) AS std_birth_date,
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
                   xl.EXCEPTION_TYPE                              AS language_exception_type
              FROM dq d
              LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
              LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
              LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = d.rc:exception_code::VARCHAR
              LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language')
        ),
        -- Exp_Consolidate_Exceptions / exp_Party_Consolidation + Rtr_Exception groups
        routed AS (
            SELECT d.*,
                   TRIM(d.pkey_src_object)                                   AS pkey_trim,   -- o_PKEY_SRC_OBJECT
                   TRIM(d.pkey_src_object) || '|' || :P_RLE_BO_CLASS_CD_MEMBER AS rle_pkey,
                   d.gender_exception_description IS NOT NULL                AS grp_gender,
                   d.birth_exception_code IS NOT NULL                        AS grp_birth,
                   (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD') AS grp_ethnicity,
                   (d.race_exception_desc IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD')      AS grp_race,
                   (d.language_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD')  AS grp_language
              FROM dq2 d
        )
        SELECT r.*,
               1 /* TIMELINE: VERSION_SEQ hard-coded */                AS version_seq,
               1                                                        AS hub_state_ind,
               :l_run_ts                                                AS run_ts,
               :c_exc_mapping                                           AS exc_mapping,
               :P_PTY_BO_CLASS_CD_MEMBER                                AS pty_bo_class_cd,
               :P_RLE_BO_CLASS_CD_MEMBER                                AS rle_bo_class_cd,
               r.BIRTH_WT_LB * 453.6 + r.BIRTH_WT_OZ * 28.35            AS birth_wght_grms,
               TO_VARCHAR(r.DOB, 'MM/DD/YYYY')                          AS dob_text,
               'Gender'                                                 AS attr_gender,
               'Birth Date'                                             AS attr_birth,
               'Ethnicity_Cd'                                           AS attr_ethnicity,
               'Race_Cd'                                                AS attr_race,
               'Language_Cd'                                            AS attr_language,
               /* BAD DATA: unique keys Snowflake does not enforce (first row per key; key not yet in the table) */
               (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
                AND xp.PKEY_SRC_OBJECT IS NULL)                         AS uq_pty,
               (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
                AND xr2.PKEY_SRC_OBJECT IS NULL)                        AS uq_rle,
               ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.pkey_src_object, r.ID, r.gender_exception_type,
                                               r.gender_exception_code ORDER BY r.ID) = 1        AS uq_gender,
               ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.pkey_src_object, r.ID, r.birth_exception_type,
                                               r.birth_exception_code ORDER BY r.ID) = 1         AS uq_birth,
               ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.pkey_src_object, r.ID,
                                               r.ethnicity_exception_type, r.ethnicity_exception_code
                                      ORDER BY r.ID) = 1                                         AS uq_ethnicity,
               ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.pkey_src_object, r.ID, r.race_exception_type,
                                               r.race_exception_cd ORDER BY r.ID) = 1            AS uq_race,
               ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.pkey_src_object, r.ID,
                                               r.language_exception_type, r.language_exception_code
                                      ORDER BY r.ID) = 1                                         AS uq_language
          FROM routed r
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY WHERE VERSION_SEQ = 1) xp
                 ON xp.PKEY_SRC_OBJECT = r.pkey_trim
          LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE WHERE VERSION_SEQ = 1) xr2
                 ON xr2.PKEY_SRC_OBJECT = r.rle_pkey
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert (C_S_ECI_PTY, C_S_ECI_PTY_RLE, exceptions)', :l_rows)
      INTO :l_line;
    l_log := l_log || l_line;

    COMMIT;
    RETURN l_log;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
