--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_OnGoing (workflow wf_TRS_Stage_Load_1_Ongoing,
-- first step).
--
-- TIERS individuals (STG_TRS_D_DC_INDV and STG_TRS_D_CV_DC_MCI_INDV) that are valid today (custom SQL: new valid
-- individuals plus the existing valid members, minus today's inactivations and earlier deactivations):
--   -> exp_interface: party key = INDV_ID || '|DC_INDV' for DC_INDV rows, INDV_ID for MCI rows
--   -> name standardization (with prefix and suffix), gender, birth date, race (code), ethnicity (code); death date
--      after the run start -> 'Invalid_Death_Date' (looked up in EXC_LOOKUP_CODE_VALUE)
--   -> rtr_Invalid_Party (a row goes to every matching group):
--        Invalid_Party_Name  (standardized first or last name blank) -> EXC_STG_BAD_REC_MEMB
--        Invalid_Gender_Code                                         -> EXC_STG_BAD_REC_MEMB
--        Invalid_Death_Date  (configured exception found)            -> EXC_STG_BAD_REC_MEMB
--        Invalid_BirthDate                                           -> EXC_STG_BAD_REC_MEMB
--        Valid_Party (first OR last name present)
--          -> srtr_Dedup_Rec (distinct) -> fltr_Dups (TIMELINE)
--             -> Sorter1 + Aggregator1 (one row per party key)      -> C_S_TRS_PTY
--             -> Sorter  + Aggregator  (one row per role key)       -> C_S_TRS_PTY_RLE
--             -> lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members (key not yet valid) -> STG_TRS_VALID_MEMBERS
--             -> Fil_Race_Exceptions / Fil_Ethnicity_Exceptions (configured exception) -> EXC_STG_BAD_REC_MEMB
--
-- VALIDATION: fn_snow_helper15_common name (V_LOOKUP_CODE_VALUE PREFIX / SUFFIX for 'TRS'), fn_snow_helper17_common
--   gender, fn_snow_helper16_common birth date, fn_snow_helper18_common race / ethnicity (V_LOOKUP_CODE_VALUE RACE /
--   ETHNICITY), death date > run start. The gender, death, race and ethnicity groups fire only when the exception is
--   configured in EXC_LOOKUP_CODE_VALUE (docs/common_insights.md section 3).
-- BAD DATA: a party with only one of its names is loaded AND logged (Valid_Party is first OR last name). Gender and
--   death-date problems never reject a party. The race / ethnicity exception rows write the MASTER code as
--   ATTRIBUTE_VALUE (fltr_Dups.Race_Cd is linked from MDM_Race_Cd), which is NULL exactly when the exception fires
--   (docs/common_insights.md 1.8); these two targets are fed by a dynamic port group (FieldMapPort), resolved field by
--   field. C_S_TRS_PTY.HUB_STATE_IND, UPDATED_BY, CREATE_DATE, CREATOR, FLAG_SRC and ROWID_OBJECT / DELETED_* are
--   linked to unfed ports (NULL); the same holds for the role table. The stored source filter INDV_ID = 504937068 is
--   not part of the custom query and is not applied. Unique keys Snowflake does not enforce are applied:
--   C_S_TRS_PTY / C_S_TRS_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ), STG_TRS_VALID_MEMBERS (PTY_PK) and
--   EXC_STG_BAD_REC_MEMB.
-- An IDQ aggregator without aggregate functions returns the LAST row of each group in arrival order. The rows arrive
-- in srtr_Dedup_Rec order (party key, update date, INDV_ID, SRC_TBL, gender, suffix, first, prefix, last, middle,
-- birth date, full name; ascending, NULL high); ROW_NUMBER() over the reverse of that order picks the same row.
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Party_Consolidation: VERSION_SEQ_NUM is hard-coded to 1 (the MD5 / version comparison is commented out in
--     IDQ); DUP_RANK is computed by IDQ but not written - not computed here.
--   * fltr_Dups keeps VERSION_SEQ_NUM = 1, i.e. every row (a no-op).
--   * PERIOD_END_DATE = MAX(PERIOD_END_DATE) of a port that is not fed (NULL); PERIOD_REFERENCE_TIME and
--     TIMELINE_ACTION are linked to unfed ports (NULL); PERIOD_START_DATE = CREATE_DT.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',      -- $PTY_BO_CLASS_CD_Member
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',    -- $RLE_BO_CLASS_CD_Member
    P_DC_INDV_TBL_SRC        VARCHAR DEFAULT 'DC_INDV',   -- $DC_INDV_TBL_SRC
    P_MCI_TBL_SRC            VARCHAR DEFAULT 'MCI'        -- $MCI_TBL_SRC
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY, C_S_TRS_PTY_RLE. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        -- rtr_Invalid_Party groups (every source row, before the de-duplication) ----------------------------------
        -- Invalid_Party_Name -> exp_Invalid_Party_Name -> Write_Invalid_Party_Name
        WHEN row_kind = 'ROUTER' AND name_missing AND uq_exc_name THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, SRC_SYS, DEATH_DT, MAPPING_NAME, MIDDLE_NAME, LAST_NAME, FIRST_NAME,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, RUN_DATE, EXCEPTION_CODE, SRC_SYS_ID_1, EXCEPTION_TYPE,
                  EXCEPTION_DESC)
            VALUES (CREATE_DT, src_sys, DEATH_DT, mapping_name, std_mdl_name, std_lst_name, std_first_name,
                    name_attribute_name, name_attribute_value, run_ts, name_exception_code, pkey_src_object,
                    name_exception_type, name_exception_desc)
        -- Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN row_kind = 'ROUTER' AND gender_exception_description IS NOT NULL AND uq_exc_gender THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (GENDER, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC,
                  EXCEPTION_TYPE, BIRTH_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  DEATH_DT, RUN_DATE, SRC_SYS_ID_1)
            VALUES (GENDER_CD, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, src_sys,
                    gender_exception_code, gender_exception_description, gender_exception_type, std_birth_date,
                    attr_gender, mapping_name, CREATE_DT, GENDER_CD, DEATH_DT, run_ts, pkey_src_object)
        -- Invalid_Death_Date -> Write_Invalid_Party_DeathDate
        WHEN row_kind = 'ROUTER' AND death_exception_desc IS NOT NULL AND uq_exc_death THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, GENDER, BIRTH_DATE, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE, DEATH_DT, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  RUN_DATE, SRC_SYS_ID_1)
            VALUES (src_sys, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, GENDER_CD,
                    std_birth_date, death_exception_lkp_code, death_exception_desc, death_exception_type, DEATH_DT,
                    death_text, attr_death, CREATE_DT, run_ts, pkey_src_object)
        -- Invalid_BirthDate -> Write_Invalid_Party_BirthDate
        WHEN row_kind = 'ROUTER' AND birth_exception_code IS NOT NULL AND uq_exc_birth THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, RUN_DATE, PREFIX, EXCEPTION_CODE, EXCEPTION_TYPE,
                  EXCEPTION_DESC, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, DEATH_DT,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1)
            VALUES (src_sys, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, run_ts, std_prfx_name,
                    birth_exception_code, birth_exception_type, birth_exception_description, std_birth_date,
                    GENDER_CD, attr_birth, mapping_name, CREATE_DT, DEATH_DT, dob_text, pkey_src_object)
        -- Valid_Party -> srtr_Dedup_Rec (distinct) -> fltr_Dups (TIMELINE: VERSION_SEQ_NUM = 1, always true) -------
        -- Sorter1 + Aggregator1 (last row per party key) -> exp_TRS_Party_Load -> Write_C_S_TRS_PTY
        WHEN row_kind = 'DEDUP' AND rn_pty = 1 AND uq_pty THEN
            INTO C_S_TRS_PTY
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, GNDR_CD, SFX_NM,
                  PTY_BO_CLASS_CD, FRST_NM, PRFX_NM, LST_NM, MDL_NM, FULL_NM, BIRTH_DT, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
                  HUB_STATE_IND, FLAG_SRC, DEATH_DT, SRC_FULL_NM, PERIOD_START_DATE, PERIOD_END_DATE, SRC_LAST_UPD_DT,
                  SRC_ROWID, RACE_CD, ETHNCTY, SRC_ETHNCTY, SRC_RACE_CD)
            VALUES (pkey_trim, NULL, NULL, NULL, NULL, mdm_gender_code, std_sfx_name, pty_bo_class_cd,
                    std_first_name, std_prfx_name, std_lst_name, std_mdl_name, std_full_name, std_birth_date,
                    version_seq, NULL, NULL, run_ts, NULL, NULL, NULL, NULL, NULL, DEATH_DT, src_full_name,
                    CREATE_DT, NULL, CREATE_DT, pkey_trim, race_mstr, ethnicity_mstr, ETHNICITY_CD, RACE_CD)
        -- Sorter + Aggregator (last row per role key) -> exp_TRS_Pty_Rle_Load -> Write_C_S_TRS_PTY_RLE
        WHEN row_kind = 'DEDUP' AND rn_pty = 1 AND uq_rle THEN
            INTO C_S_TRS_PTY_RLE
                 (PTY_FK, PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, RLE_BO_CLASS_CD,
                  VERSION_SEQ, PERIOD_END_DATE, PERIOD_START_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, UPDATED_BY,
                  CREATE_DATE, CREATOR, SRC_LAST_UPD_DT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE)
            VALUES (pkey_trim, rle_pkey, NULL, NULL, NULL, NULL, rle_bo_class_cd, version_seq, NULL, CREATE_DT, NULL,
                    NULL, NULL, NULL, NULL, CREATE_DT, NULL, rle_pkey, run_ts)
        -- lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members + srtr_Pkey + agg_Valid_Members -> Write_Stg_TRS_Valid_Members
        WHEN row_kind = 'DEDUP' AND rn_pty = 1 AND NOT is_valid_member THEN
            INTO STG_TRS_VALID_MEMBERS (SRC_TBL, PTY_PK, INDV_ID, CREATE_DATE)
            VALUES (SRC_TBL, pkey_trim, INDV_ID, run_ts)
        -- Fil_Race_Exceptions -> Exp_Race_Exceptions -> Write_Invalid_Party_Race (dynamic port group)
        WHEN row_kind = 'DEDUP' AND race_exception_code IS NOT NULL AND uq_exc_race THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, DEATH_DT, GENDER, BIRTH_DATE, MIDDLE_NAME, LAST_NAME, PREFIX, FIRST_NAME, SUFFIX,
                  PERIOD_START_DATE, RUN_DATE, MAPPING_NAME)
            VALUES (src_sys, pkey_trim, race_exception_type, race_exception_desc, race_exception_code, attr_race,
                    race_mstr, DEATH_DT, mdm_gender_code, std_birth_date, std_mdl_name, std_lst_name, std_prfx_name,
                    std_first_name, std_sfx_name, CREATE_DT, run_ts, mapping_name)
        -- Fil_Ethnicity_Exceptions -> Exp_Ethnicity_Exceptions -> Write_Invalid_Party_Ethnicity (dynamic port group)
        WHEN row_kind = 'DEDUP' AND ethnicity_exception_code IS NOT NULL AND uq_exc_ethnicity THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, PERIOD_START_DATE, DEATH_DT, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, PREFIX, LAST_NAME, MIDDLE_NAME, FIRST_NAME, SUFFIX, GENDER,
                  MAPPING_NAME)
            VALUES (src_sys, pkey_trim, attr_ethnicity, ethnicity_mstr, CREATE_DT, DEATH_DT, ethnicity_exception_code,
                    ethnicity_exception_desc, ethnicity_exception_type, run_ts, std_prfx_name, std_lst_name,
                    std_mdl_name, std_first_name, std_sfx_name, mdm_gender_code, mapping_name)
    SELECT *
      FROM (
        WITH
        lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
        lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
        lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
        -- Read_STG_TRS_D_DC_INDV (custom SQL, query mode SEMI; $MCI_TBL_SRC / $DC_INDV_TBL_SRC substituted)
        new_valid_indvs AS (
            SELECT DISTINCT indv_id FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA WHERE conversion_ind = 'C'
            UNION
            SELECT DISTINCT indv_id FROM STG_TRS_D_DC_INDV
             WHERE FILE_CLEARANCE_SW = 'Y' AND Inactive_ind = 'N' AND delete_sw = 'N'
            UNION
            SELECT DISTINCT indv_id FROM STG_TRS_D_CV_DC_MCI_INDV WHERE Inactive_ind = 'N'
            UNION
            SELECT DISTINCT indv_id FROM STG_TRS_VALID_MEMBERS
            MINUS                              -- remove any records that will be inactivated today
            SELECT DISTINCT indv_id FROM STG_TRS_D_DC_INDV WHERE Inactive_ind = 'Y' OR delete_sw = 'Y'
            MINUS
            SELECT DISTINCT indv_id FROM STG_TRS_D_CV_DC_MCI_INDV WHERE Inactive_ind = 'Y'
            MINUS                              -- re-runs and re-activations
            SELECT indv_id FROM STG_TRS_DEACTIVED_MEMBERS
        ),
        all_indv AS (
            SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
                   NULL AS SSA_VAL_SW, NULL AS FILE_CL_SW, DOB_DT, NULL AS DEATH_DT, CREATE_DT,
                   :P_MCI_TBL_SRC AS SRC_TBL
              FROM STG_TRS_D_CV_DC_MCI_INDV
            UNION ALL
            SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
                   SSA_VALIDATION_SW, FILE_CLEARANCE_SW, DOB_DT, DEATH_DT, CREATE_DT, :P_DC_INDV_TBL_SRC
              FROM STG_TRS_D_DC_INDV
        ),
        src AS (
            SELECT DISTINCT a.INDV_ID, RTRIM(LTRIM(a.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(a.MID_NAME)) AS MID_NAME,
                   RTRIM(LTRIM(a.LAST_NAME)) AS LAST_NAME, RTRIM(a.SUFX_NAME) AS SUFX_NAME,
                   RTRIM(a.PREFIX_NAME) AS PREFIX_NAME, a.GENDER_CD, a.RACE_CD, a.ETHNICITY_CD, a.SSA_VAL_SW,
                   a.FILE_CL_SW, a.DOB_DT, a.CREATE_DT, a.SRC_TBL, a.DEATH_DT
              FROM all_indv a
             INNER JOIN new_valid_indvs f ON f.indv_id = a.indv_id
        ),
        -- exp_Tiers_Data_Load + exp_interface + mapplets (step 1: lookups and rule functions) + exp_Validate_Death_Dt
        dq AS (
            SELECT s.*,
                   IFF(s.SRC_TBL = :P_DC_INDV_TBL_SRC, TO_VARCHAR(s.INDV_ID) || '|' || :P_DC_INDV_TBL_SRC,
                       TO_VARCHAR(s.INDV_ID))                                                     AS pkey_src_object,
                   TRIM(NVL(s.FIRST_NAME, '') || IFF(s.MID_NAME IS NOT NULL, ' ' || TRIM(s.MID_NAME), '')
                        || ' ' || NVL(LTRIM(s.LAST_NAME), ''))                                    AS src_full_name,
                   fn_snow_helper15_common(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME,
                       TRIM(NVL(s.FIRST_NAME, '') || IFF(s.MID_NAME IS NOT NULL, ' ' || TRIM(s.MID_NAME), '')
                            || ' ' || NVL(LTRIM(s.LAST_NAME), '')),
                       s.PREFIX_NAME, s.SUFX_NAME, pfx.MSTR_CODE_VALUE, sfx.MSTR_CODE_VALUE,
                       jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)                                  AS nm,
                   fn_snow_helper17_common(s.GENDER_CD, 'Indv', 'TRS')                            AS gd,
                   /* VALIDATION */ fn_snow_helper16_common(s.DOB_DT, 'Indv', 'TRS', :l_run_ts)  AS birth_exception_code,
                   rc.MSTR_CODE_VALUE                                                             AS race_mstr,
                   et.MSTR_CODE_VALUE                                                             AS ethnicity_mstr,
                   /* VALIDATION */ IFF(s.DEATH_DT > :l_run_ts, 'Invalid_Death_Date', NULL)      AS death_exception_code
              FROM src s
              LEFT JOIN lkp_cv pfx ON pfx.CODE_TYPE = 'PREFIX' AND pfx.SRC_SYS = 'TRS' AND pfx.SRC_CODE_VALUE = s.PREFIX_NAME
              LEFT JOIN lkp_cv sfx ON sfx.CODE_TYPE = 'SUFFIX' AND sfx.SRC_SYS = 'TRS' AND sfx.SRC_CODE_VALUE = s.SUFX_NAME
              LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(s.FIRST_NAME)) AND jf.IS_FIRST_JUNK
              LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(s.LAST_NAME)) AND jl.IS_LAST_JUNK
              LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'TRS' AND rc.SRC_CODE_VALUE = s.RACE_CD
              LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'TRS' AND et.SRC_CODE_VALUE = s.ETHNICITY_CD
        ),
        -- mapplets, step 2: the exception catalogue; lkp_Exc_Death_Dt
        base AS (
            SELECT d.*,
                   TRIM(d.pkey_src_object)               AS pkey_trim,
                   d.nm:first_name::VARCHAR              AS std_first_name,
                   d.nm:middle_name::VARCHAR             AS std_mdl_name,
                   d.nm:last_name::VARCHAR               AS std_lst_name,
                   d.nm:full_name::VARCHAR               AS std_full_name,
                   d.nm:prfx_name::VARCHAR               AS std_prfx_name,
                   d.nm:sfx_name::VARCHAR                AS std_sfx_name,
                   d.gd:mdm_gender_code::VARCHAR         AS mdm_gender_code,
                   d.gd:exception_code::VARCHAR          AS gender_exception_code,
                   xg.EXCEPTION_DESC                     AS gender_exception_description,
                   xg.EXCEPTION_TYPE                     AS gender_exception_type,
                   /* BAD DATA */ IFF(d.birth_exception_code IS NULL, d.DOB_DT, NULL) AS std_birth_date,
                   xb.EXCEPTION_DESC                     AS birth_exception_description,
                   xb.EXCEPTION_TYPE                     AS birth_exception_type,
                   xr.EXCEPTION_CODE                     AS race_exception_code,
                   xr.EXCEPTION_DESC                     AS race_exception_desc,
                   xr.EXCEPTION_TYPE                     AS race_exception_type,
                   xe.EXCEPTION_CODE                     AS ethnicity_exception_code,
                   xe.EXCEPTION_DESC                     AS ethnicity_exception_desc,
                   xe.EXCEPTION_TYPE                     AS ethnicity_exception_type,
                   xd.EXCEPTION_CODE                     AS death_exception_lkp_code,
                   xd.EXCEPTION_DESC                     AS death_exception_desc,
                   xd.EXCEPTION_TYPE                     AS death_exception_type,
                   /* VALIDATION */ (fn_snow_helper03_common(d.nm:first_name::VARCHAR)
                                     OR fn_snow_helper03_common(d.nm:last_name::VARCHAR)) AS name_missing
              FROM dq d
              LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = d.gd:exception_code::VARCHAR
              LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
              LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
              LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
              LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = d.death_exception_code
        ),
        -- rtr_Invalid_Party (router rows) + exp_Invalid_Party_Name
        router AS (
            SELECT b.*,
                   CASE WHEN fn_snow_helper03_common(b.std_first_name) THEN 'Missing_First_Name'
                        WHEN fn_snow_helper03_common(b.std_lst_name) THEN 'Missing_Last_Name' END  AS name_exception_code,
                   CASE WHEN fn_snow_helper03_common(b.std_first_name) THEN 'First Name'
                        WHEN fn_snow_helper03_common(b.std_lst_name) THEN 'Last Name' END          AS name_attribute_name,
                   CASE WHEN fn_snow_helper03_common(b.std_first_name) THEN b.std_first_name
                        WHEN fn_snow_helper03_common(b.std_lst_name) THEN b.std_lst_name END       AS name_attribute_value
              FROM base b
        ),
        router_flagged AS (
            SELECT r.*,
                   xn.EXCEPTION_TYPE AS name_exception_type,
                   xn.EXCEPTION_DESC AS name_exception_desc,
                   /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
                   ROW_NUMBER() OVER (PARTITION BY r.name_missing, r.pkey_src_object, xn.EXCEPTION_TYPE,
                                                   r.name_exception_code ORDER BY r.CREATE_DT DESC) = 1   AS uq_exc_name,
                   ROW_NUMBER() OVER (PARTITION BY r.gender_exception_description IS NOT NULL, r.pkey_src_object,
                                                   r.gender_exception_type, r.gender_exception_code
                                          ORDER BY r.CREATE_DT DESC) = 1                                 AS uq_exc_gender,
                   ROW_NUMBER() OVER (PARTITION BY r.death_exception_desc IS NOT NULL, r.pkey_src_object,
                                                   r.death_exception_type, r.death_exception_lkp_code
                                          ORDER BY r.CREATE_DT DESC) = 1                                 AS uq_exc_death,
                   ROW_NUMBER() OVER (PARTITION BY r.birth_exception_code IS NOT NULL, r.pkey_src_object,
                                                   r.birth_exception_type, r.birth_exception_code
                                          ORDER BY r.CREATE_DT DESC) = 1                                 AS uq_exc_birth
              FROM router r
              LEFT JOIN lkp_exc xn ON xn.EXCEPTION_CODE = r.name_exception_code
        ),
        -- srtr_Dedup_Rec (distinct over the ports that reach the C_S / valid-member / race / ethnicity targets)
        dedup AS (
            SELECT DISTINCT pkey_trim, CREATE_DT, INDV_ID, SRC_TBL, mdm_gender_code, std_sfx_name, std_first_name,
                   std_prfx_name, std_lst_name, std_mdl_name, std_birth_date, std_full_name, DEATH_DT, src_full_name,
                   RACE_CD, race_mstr, race_exception_code, race_exception_desc, race_exception_type, ETHNICITY_CD,
                   ethnicity_mstr, ethnicity_exception_code, ethnicity_exception_desc, ethnicity_exception_type
              FROM base
             -- rtr_Invalid_Party.Valid_Party: LENGTH(RTRIM(first)) != 0 OR LENGTH(RTRIM(last)) != 0
             --                                OR NOT ISNULL(first) OR NOT ISNULL(last)
             WHERE std_first_name IS NOT NULL OR std_lst_name IS NOT NULL
        ),
        dedup_ranked AS (
            SELECT x.*,
                   -- Aggregator1 / Aggregator / agg_Valid_Members: last row per key in srtr_Dedup_Rec order (NULL high)
                   ROW_NUMBER() OVER (PARTITION BY x.pkey_trim
                                      ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID DESC NULLS FIRST,
                                               x.SRC_TBL DESC NULLS FIRST, x.mdm_gender_code DESC NULLS FIRST,
                                               x.std_sfx_name DESC NULLS FIRST, x.std_first_name DESC NULLS FIRST,
                                               x.std_prfx_name DESC NULLS FIRST, x.std_lst_name DESC NULLS FIRST,
                                               x.std_mdl_name DESC NULLS FIRST, x.std_birth_date DESC NULLS FIRST,
                                               x.std_full_name DESC NULLS FIRST)               AS rn_pty,
                   -- lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members: ISNULL(PTY_PK_EXISTS)
                   vm.PTY_PK IS NOT NULL                                                       AS is_valid_member,
                   xp.PKEY_SRC_OBJECT IS NULL                                                  AS uq_pty,
                   xr2.PKEY_SRC_OBJECT IS NULL                                                 AS uq_rle,
                   /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
                   ROW_NUMBER() OVER (PARTITION BY x.race_exception_code IS NOT NULL, x.pkey_trim,
                                                   x.race_exception_type, x.race_exception_code
                                          ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID) = 1       AS uq_exc_race,
                   ROW_NUMBER() OVER (PARTITION BY x.ethnicity_exception_code IS NOT NULL, x.pkey_trim,
                                                   x.ethnicity_exception_type, x.ethnicity_exception_code
                                          ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID) = 1       AS uq_exc_ethnicity
              FROM dedup x
              LEFT JOIN (SELECT DISTINCT PTY_PK FROM STG_TRS_VALID_MEMBERS) vm ON vm.PTY_PK = x.pkey_trim
              /* BAD DATA: unique keys Snowflake does not enforce (key not yet in the table) */
              LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY WHERE VERSION_SEQ = 1) xp
                     ON xp.PKEY_SRC_OBJECT = x.pkey_trim
              LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE WHERE VERSION_SEQ = 1) xr2
                     ON xr2.PKEY_SRC_OBJECT = x.pkey_trim || '|' || :P_RLE_BO_CLASS_CD_MEMBER
        ),
        -- one statement, two row kinds: the router rows (exceptions) and the de-duplicated valid rows
        both_kinds AS (
            SELECT 'ROUTER' AS row_kind, b.pkey_src_object, b.pkey_trim, b.INDV_ID, b.SRC_TBL, b.CREATE_DT,
                   b.DEATH_DT, b.DOB_DT, b.GENDER_CD, b.RACE_CD, b.ETHNICITY_CD, b.src_full_name, b.std_first_name,
                   b.std_mdl_name, b.std_lst_name, b.std_full_name, b.std_prfx_name, b.std_sfx_name,
                   b.mdm_gender_code, b.gender_exception_code, b.gender_exception_description,
                   b.gender_exception_type, b.std_birth_date, b.birth_exception_code, b.birth_exception_description,
                   b.birth_exception_type, b.race_mstr, b.race_exception_code, b.race_exception_desc,
                   b.race_exception_type, b.ethnicity_mstr, b.ethnicity_exception_code, b.ethnicity_exception_desc,
                   b.ethnicity_exception_type, b.death_exception_lkp_code, b.death_exception_desc,
                   b.death_exception_type, b.name_missing, b.name_exception_code, b.name_exception_type,
                   b.name_exception_desc, b.name_attribute_name, b.name_attribute_value,
                   b.uq_exc_name, b.uq_exc_gender, b.uq_exc_death, b.uq_exc_birth,
                   NULL::NUMBER AS rn_pty, NULL::BOOLEAN AS is_valid_member, NULL::BOOLEAN AS uq_pty,
                   NULL::BOOLEAN AS uq_rle, NULL::BOOLEAN AS uq_exc_race, NULL::BOOLEAN AS uq_exc_ethnicity
              FROM router_flagged b
            UNION ALL
            SELECT 'DEDUP', NULL, r.pkey_trim, r.INDV_ID, r.SRC_TBL, r.CREATE_DT, r.DEATH_DT, NULL, NULL, r.RACE_CD,
                   r.ETHNICITY_CD, r.src_full_name, r.std_first_name, r.std_mdl_name, r.std_lst_name,
                   r.std_full_name, r.std_prfx_name, r.std_sfx_name, r.mdm_gender_code, NULL, NULL, NULL,
                   r.std_birth_date, NULL, NULL, NULL, r.race_mstr, r.race_exception_code, r.race_exception_desc,
                   r.race_exception_type, r.ethnicity_mstr, r.ethnicity_exception_code, r.ethnicity_exception_desc,
                   r.ethnicity_exception_type, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                   NULL, NULL, NULL, NULL,
                   r.rn_pty, r.is_valid_member, r.uq_pty, r.uq_rle, r.uq_exc_race, r.uq_exc_ethnicity
              FROM dedup_ranked r
        )
        SELECT k.*,
               k.pkey_trim || '|' || :P_RLE_BO_CLASS_CD_MEMBER          AS rle_pkey,
               1 /* TIMELINE: VERSION_SEQ_NUM hard-coded */             AS version_seq,
               'TRS'                                                     AS src_sys,
               :l_run_ts                                                 AS run_ts,
               :c_mapping                                                AS mapping_name,
               :P_PTY_BO_CLASS_CD_MEMBER                                 AS pty_bo_class_cd,
               :P_RLE_BO_CLASS_CD_MEMBER                                 AS rle_bo_class_cd,
               TO_VARCHAR(k.DEATH_DT, 'MM/DD/YYYY HH24:MI:SS')           AS death_text,   -- IDQ default date-to-string
               TO_VARCHAR(k.DOB_DT, 'MM/DD/YYYY')                        AS dob_text,
               'Gender'                                                  AS attr_gender,
               'Death Date'                                              AS attr_death,
               'Birth Date'                                              AS attr_birth,
               'Race_Cd'                                                 AS attr_race,
               'Ethnicity_Cd'                                            AS attr_ethnicity
          FROM both_kinds k
      );
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping,
               'insert (C_S_TRS_PTY, C_S_TRS_PTY_RLE, STG_TRS_VALID_MEMBERS, exceptions)', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
