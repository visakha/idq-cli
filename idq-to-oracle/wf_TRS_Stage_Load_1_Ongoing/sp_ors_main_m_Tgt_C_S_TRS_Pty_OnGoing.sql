--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_OnGoing (workflow wf_TRS_Stage_Load_1_Ongoing, first step).
--
-- TIERS individuals (STG_TRS_D_DC_INDV and STG_TRS_D_CV_DC_MCI_INDV) that are valid today (custom SQL: new valid
-- individuals plus the existing valid members, minus today's inactivations and earlier deactivations):
--   -> exp_interface: party key = INDV_ID || '|DC_INDV' for DC_INDV rows, INDV_ID for MCI rows
--   -> name standardization, gender, birth date, race (code), ethnicity (code); death date after SYSDATE ->
--      'Invalid_Death_Date' (looked up in EXC_LOOKUP_CODE_VALUE)
--   -> rtr_Invalid_Party (a row goes to every matching group):
--        Invalid_Party_Name  (standardized first or last name blank) -> EXC_STG_BAD_REC_MEMB
--        Invalid_Gender_Code                                         -> EXC_STG_BAD_REC_MEMB
--        Invalid_Death_Date  (configured exception found)            -> EXC_STG_BAD_REC_MEMB
--        Invalid_BirthDate                                           -> EXC_STG_BAD_REC_MEMB
--        Valid_Party (first OR last name present)
--          -> srtr_Dedup_Rec (distinct) -> fltr_Dups (TIMELINE, see below)
--             -> Sorter1 + Aggregator1 (one row per party key)      -> C_S_TRS_PTY        (insert only, never truncated)
--             -> Sorter  + Aggregator  (one row per role key)       -> C_S_TRS_PTY_RLE    (insert only, never truncated)
--             -> lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members (key not yet valid)
--                -> srtr_Pkey + agg_Valid_Members (one row per key)  -> STG_TRS_VALID_MEMBERS
--             -> Fil_Race_Exceptions      (race code does not translate, configured) -> EXC_STG_BAD_REC_MEMB
--             -> Fil_Ethnicity_Exceptions (ethnicity code does not translate, configured) -> EXC_STG_BAD_REC_MEMB
--
-- An IDQ aggregator without aggregate functions returns the LAST row of each group in arrival order. The rows arrive
-- in srtr_Dedup_Rec order (party key, update date, INDV_ID, SRC_TBL, gender, suffix, first, prefix, last, middle,
-- birth date, full name; ascending, NULL high), which the downstream sorters on the key alone are taken to preserve;
-- ROW_NUMBER() over the reverse of that order picks the same row.
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Party_Consolidation: VERSION_SEQ_NUM is hard-coded to 1 (the MD5 / version comparison is commented out in
--     IDQ); DUP_RANK is computed by IDQ but not written - not computed here.
--   * fltr_Dups keeps VERSION_SEQ_NUM = 1, i.e. every row: kept as a no-op condition below.
--   * PERIOD_END_DATE = MAX(PERIOD_END_DATE) of a port that is not fed (NULL); PERIOD_REFERENCE_TIME and
--     TIMELINE_ACTION are linked to unfed ports (NULL); PERIOD_START_DATE = CREATE_DT.
--
-- IDQ quirks kept:
--   * The race / ethnicity exception rows write the MASTER code as ATTRIBUTE_VALUE (fltr_Dups.Race_Cd is linked from
--     MDM_Race_Cd), which is NULL exactly when the exception fires. These two targets are fed by a dynamic port group
--     (FieldMapPort), resolved field by field.
--   * C_S_TRS_PTY.HUB_STATE_IND, UPDATED_BY, CREATE_DATE, CREATOR, FLAG_SRC and ROWID_OBJECT / DELETED_* are linked
--     to unfed ports (NULL); the same holds for the role table.
--   * The stored source filter INDV_ID = 504937068 is not part of the custom query and is not applied.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing (
    p_pty_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Indv',      -- $PTY_BO_CLASS_CD_Member
    p_rle_bo_class_cd_member  IN VARCHAR2 DEFAULT 'Member',    -- $RLE_BO_CLASS_CD_Member
    p_dc_indv_tbl_src         IN VARCHAR2 DEFAULT 'DC_INDV',   -- $DC_INDV_TBL_SRC
    p_mci_tbl_src             IN VARCHAR2 DEFAULT 'MCI'        -- $MCI_TBL_SRC
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_OnGoing';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
BEGIN
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY, C_S_TRS_PTY_RLE. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT ALL
        ------------------------------------------------------------------------------------------------------------
        -- rtr_Invalid_Party groups (every source row, before the de-duplication)
        ------------------------------------------------------------------------------------------------------------
        -- Invalid_Party_Name -> exp_Invalid_Party_Name -> Write_Invalid_Party_Name
        WHEN row_kind = 'ROUTER' AND name_missing = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, SRC_SYS, DEATH_DT, MAPPING_NAME, MIDDLE_NAME, LAST_NAME, FIRST_NAME,
                  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, RUN_DATE, EXCEPTION_CODE, SRC_SYS_ID_1, EXCEPTION_TYPE,
                  EXCEPTION_DESC)
            VALUES (CREATE_DT, 'TRS', DEATH_DT, 'm_Tgt_C_S_TRS_Pty_OnGoing', std_mdl_name, std_lst_name,
                    std_first_name, name_attribute_name, name_attribute_value, l_run_ts, name_exception_code,
                    pkey_src_object, fn_ors_helper05_common(name_exception_code),
                    fn_ors_helper04_common(name_exception_code))
        -- Invalid_Gender_Code -> Write_Invalid_Party_Gender
        WHEN row_kind = 'ROUTER' AND gender_exception_description IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (GENDER, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC,
                  EXCEPTION_TYPE, BIRTH_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, ATTRIBUTE_VALUE,
                  DEATH_DT, RUN_DATE, SRC_SYS_ID_1)
            VALUES (GENDER_CD, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, 'TRS',
                    gender_exception_code, gender_exception_description, gender_exception_type, std_birth_date,
                    'Gender', c_mapping, CREATE_DT, GENDER_CD, DEATH_DT, l_run_ts, pkey_src_object)
        -- Invalid_Death_Date -> Write_Invalid_Party_DeathDate
        WHEN row_kind = 'ROUTER' AND death_exception_desc IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, GENDER, BIRTH_DATE, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE, DEATH_DT, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, PERIOD_START_DATE,
                  RUN_DATE, SRC_SYS_ID_1)
            VALUES ('TRS', std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, GENDER_CD,
                    std_birth_date, death_exception_lkp_code, death_exception_desc, death_exception_type, DEATH_DT,
                    TO_CHAR(DEATH_DT, 'MM/DD/YYYY HH24:MI:SS') /* IDQ default date-to-string */, 'Death Date',
                    CREATE_DT, l_run_ts, pkey_src_object)
        -- Invalid_BirthDate -> Write_Invalid_Party_BirthDate
        WHEN row_kind = 'ROUTER' AND birth_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, RUN_DATE, PREFIX, EXCEPTION_CODE, EXCEPTION_TYPE,
                  EXCEPTION_DESC, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, DEATH_DT,
                  ATTRIBUTE_VALUE, SRC_SYS_ID_1)
            VALUES ('TRS', std_first_name, std_mdl_name, std_lst_name, std_sfx_name, l_run_ts, std_prfx_name,
                    birth_exception_code, birth_exception_type, birth_exception_description, std_birth_date,
                    GENDER_CD, birth_attribute_name, c_mapping, CREATE_DT, DEATH_DT, TO_CHAR(DOB_DT, 'MM/DD/YYYY'),
                    pkey_src_object)
        ------------------------------------------------------------------------------------------------------------
        -- Valid_Party -> srtr_Dedup_Rec (distinct) -> fltr_Dups (TIMELINE: VERSION_SEQ_NUM = 1, always true)
        ------------------------------------------------------------------------------------------------------------
        -- Sorter1 + Aggregator1 (last row per party key) -> exp_TRS_Party_Load -> Write_C_S_TRS_PTY
        WHEN row_kind = 'DEDUP' AND rn_pty = 1 THEN
            INTO C_S_TRS_PTY
                 (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, GNDR_CD, SFX_NM,
                  PTY_BO_CLASS_CD, FRST_NM, PRFX_NM, LST_NM, MDL_NM, FULL_NM, BIRTH_DT, VERSION_SEQ,
                  PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
                  HUB_STATE_IND, FLAG_SRC, DEATH_DT, SRC_FULL_NM, PERIOD_START_DATE, PERIOD_END_DATE, SRC_LAST_UPD_DT,
                  SRC_ROWID, RACE_CD, ETHNCTY, SRC_ETHNCTY, SRC_RACE_CD)
            VALUES (pkey_trim, NULL, NULL, NULL, NULL, mdm_gender_code, std_sfx_name, p_pty_bo_class_cd_member,
                    std_first_name, std_prfx_name, std_lst_name, std_mdl_name, std_full_name, std_birth_date,
                    1 /* TIMELINE: VERSION_SEQ_NUM hard-coded */, NULL /* TIMELINE: unfed */,
                    NULL /* TIMELINE: unfed */, l_run_ts, NULL, NULL, NULL, NULL, NULL, DEATH_DT, src_full_name,
                    CREATE_DT /* TIMELINE */, NULL /* TIMELINE: MAX of an unfed port */, CREATE_DT, pkey_trim,
                    race_mstr, ethnicity_mstr, ETHNICITY_CD, RACE_CD)
        -- Sorter + Aggregator (last row per role key) -> exp_TRS_Pty_Rle_Load -> Write_C_S_TRS_PTY_RLE
        WHEN row_kind = 'DEDUP' AND rn_pty = 1 THEN
            INTO C_S_TRS_PTY_RLE
                 (PTY_FK, PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, RLE_BO_CLASS_CD,
                  VERSION_SEQ, PERIOD_END_DATE, PERIOD_START_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, UPDATED_BY,
                  CREATE_DATE, CREATOR, SRC_LAST_UPD_DT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE)
            VALUES (pkey_trim, pkey_trim || '|' || p_rle_bo_class_cd_member, NULL, NULL, NULL, NULL,
                    p_rle_bo_class_cd_member, 1 /* TIMELINE: VERSION_SEQ_NUM */, NULL /* TIMELINE: MAX of unfed */,
                    CREATE_DT /* TIMELINE */, NULL /* TIMELINE */, NULL /* TIMELINE */, NULL, NULL, NULL, CREATE_DT,
                    NULL, pkey_trim || '|' || p_rle_bo_class_cd_member, l_run_ts)
        -- lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members + srtr_Pkey + agg_Valid_Members -> Write_Stg_TRS_Valid_Members
        WHEN row_kind = 'DEDUP' AND rn_pty = 1 AND is_valid_member = 0 THEN
            INTO STG_TRS_VALID_MEMBERS (SRC_TBL, PTY_PK, INDV_ID, CREATE_DATE)
            VALUES (SRC_TBL, pkey_trim, INDV_ID, l_run_ts)
        -- Fil_Race_Exceptions -> Exp_Race_Exceptions -> Write_Invalid_Party_Race (dynamic port group)
        WHEN row_kind = 'DEDUP' AND race_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_NAME,
                  ATTRIBUTE_VALUE, DEATH_DT, GENDER, BIRTH_DATE, MIDDLE_NAME, LAST_NAME, PREFIX, FIRST_NAME, SUFFIX,
                  PERIOD_START_DATE, RUN_DATE, MAPPING_NAME)
            VALUES ('TRS', pkey_trim, race_exception_type, race_exception_desc, race_exception_code, 'Race_Cd',
                    race_mstr /* IDQ: master code, NULL here */, DEATH_DT, mdm_gender_code, std_birth_date,
                    std_mdl_name, std_lst_name, std_prfx_name, std_first_name, std_sfx_name, CREATE_DT, l_run_ts,
                    c_mapping)
        -- Fil_Ethnicity_Exceptions -> Exp_Ethnicity_Exceptions -> Write_Invalid_Party_Ethnicity (dynamic port group)
        WHEN row_kind = 'DEDUP' AND ethnicity_exception_code IS NOT NULL THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, PERIOD_START_DATE, DEATH_DT, EXCEPTION_CODE,
                  EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, PREFIX, LAST_NAME, MIDDLE_NAME, FIRST_NAME, SUFFIX, GENDER,
                  MAPPING_NAME)
            VALUES ('TRS', pkey_trim, 'Ethnicity_Cd', ethnicity_mstr /* IDQ: master code, NULL here */, CREATE_DT,
                    DEATH_DT, ethnicity_exception_code, ethnicity_exception_desc, ethnicity_exception_type,
                    l_run_ts, std_prfx_name, std_lst_name, std_mdl_name, std_first_name, std_sfx_name,
                    mdm_gender_code, c_mapping)
    WITH
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
               p_mci_tbl_src AS SRC_TBL
          FROM STG_TRS_D_CV_DC_MCI_INDV
        UNION ALL
        SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
               SSA_VALIDATION_SW, FILE_CLEARANCE_SW, DOB_DT, DEATH_DT, CREATE_DT, p_dc_indv_tbl_src
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
    -- exp_Tiers_Data_Load + exp_interface + mapplets + exp_Validate_Death_Dt + lkp_Exc_Death_Dt
    dq AS (
        SELECT /*+ NO_MERGE */
               s.*,
               CASE WHEN s.SRC_TBL = p_dc_indv_tbl_src THEN TO_CHAR(s.INDV_ID) || '|' || p_dc_indv_tbl_src
                    ELSE TO_CHAR(s.INDV_ID) END                                             AS pkey_src_object,
               LTRIM(RTRIM(s.FIRST_NAME || CASE WHEN s.MID_NAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(s.MID_NAME)) END
                           || ' ' || LTRIM(s.LAST_NAME)))                                   AS src_full_name,
               fn_dq_std_name_indv_member(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME,
                   LTRIM(RTRIM(s.FIRST_NAME || CASE WHEN s.MID_NAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(s.MID_NAME)) END
                               || ' ' || LTRIM(s.LAST_NAME))),
                   s.PREFIX_NAME, s.SUFX_NAME, NULL, NULL, 'TRS')                         AS nm,
               fn_dq_valid_gender(s.GENDER_CD, 'Indv', 'TRS')                               AS gd,
               fn_dq_valid_birth_date(s.DOB_DT, 'Indv', 'TRS')                              AS bd,
               fn_dq_valid_race(s.RACE_CD, 'TRS')                                           AS rc,
               fn_dq_valid_ethnicity(s.ETHNICITY_CD, 'TRS')                                 AS et,
               CASE WHEN s.DEATH_DT > SYSDATE THEN 'Invalid_Death_Date' END                 AS death_exception_code
          FROM src s
    ),
    base AS (
        SELECT d.*,
               LTRIM(RTRIM(d.pkey_src_object))       AS pkey_trim,
               d.nm.first_name                       AS std_first_name,
               d.nm.mdl_name                         AS std_mdl_name,
               d.nm.lst_name                         AS std_lst_name,
               d.nm.full_name                        AS std_full_name,
               d.nm.prfx_name                        AS std_prfx_name,
               d.nm.sfx_name                         AS std_sfx_name,
               d.gd.mdm_gender_code                  AS mdm_gender_code,
               d.gd.gender_exception_code            AS gender_exception_code,
               d.gd.gender_exception_description     AS gender_exception_description,
               d.gd.gender_exception_type            AS gender_exception_type,
               d.bd.birth_date                       AS std_birth_date,
               d.bd.exception_code                   AS birth_exception_code,
               d.bd.exception_description            AS birth_exception_description,
               d.bd.exception_type                   AS birth_exception_type,
               d.bd.attribute_name                   AS birth_attribute_name,
               d.rc.mstr_code_value                  AS race_mstr,
               d.rc.exception_code                   AS race_exception_code,
               d.rc.exception_desc                   AS race_exception_desc,
               d.rc.exception_type                   AS race_exception_type,
               d.et.mstr_code_value                  AS ethnicity_mstr,
               d.et.exception_code                   AS ethnicity_exception_code,
               d.et.exception_desc                   AS ethnicity_exception_desc,
               d.et.exception_type                   AS ethnicity_exception_type,
               fn_ors_helper08_common(d.death_exception_code)  AS death_exception_lkp_code,
               fn_ors_helper04_common(d.death_exception_code)  AS death_exception_desc,
               fn_ors_helper05_common(d.death_exception_code)  AS death_exception_type,
               CASE WHEN RTRIM(d.nm.first_name) IS NULL OR RTRIM(d.nm.lst_name) IS NULL THEN 1 ELSE 0 END AS name_missing
          FROM dq d
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
                                           x.std_full_name DESC NULLS FIRST)                  AS rn_pty,
               -- lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members: ISNULL(PTY_PK_EXISTS)
               CASE WHEN EXISTS (SELECT 1 FROM STG_TRS_VALID_MEMBERS vm WHERE vm.PTY_PK = x.pkey_trim)
                    THEN 1 ELSE 0 END                                                         AS is_valid_member
          FROM dedup x
    )
    -- one statement, two row kinds: the router rows (exceptions) and the de-duplicated valid rows
    SELECT 'ROUTER' AS row_kind, b.pkey_src_object, b.pkey_trim, b.INDV_ID, b.SRC_TBL, b.CREATE_DT, b.DEATH_DT,
           b.DOB_DT, b.GENDER_CD, b.RACE_CD, b.ETHNICITY_CD, b.src_full_name, b.std_first_name, b.std_mdl_name,
           b.std_lst_name, b.std_full_name, b.std_prfx_name, b.std_sfx_name, b.mdm_gender_code,
           b.gender_exception_code, b.gender_exception_description, b.gender_exception_type, b.std_birth_date,
           b.birth_exception_code, b.birth_exception_description, b.birth_exception_type, b.birth_attribute_name,
           b.race_mstr, b.race_exception_code, b.race_exception_desc, b.race_exception_type, b.ethnicity_mstr,
           b.ethnicity_exception_code, b.ethnicity_exception_desc, b.ethnicity_exception_type,
           b.death_exception_lkp_code, b.death_exception_desc, b.death_exception_type, b.name_missing,
           CASE WHEN RTRIM(b.std_first_name) IS NULL THEN 'Missing_First_Name'
                WHEN RTRIM(b.std_lst_name) IS NULL THEN 'Missing_Last_Name' END           AS name_exception_code,
           CASE WHEN RTRIM(b.std_first_name) IS NULL THEN 'First Name'
                WHEN RTRIM(b.std_lst_name) IS NULL THEN 'Last Name' END                   AS name_attribute_name,
           CASE WHEN RTRIM(b.std_first_name) IS NULL THEN b.std_first_name
                WHEN RTRIM(b.std_lst_name) IS NULL THEN b.std_lst_name END                AS name_attribute_value,
           CAST(NULL AS NUMBER) AS rn_pty, CAST(NULL AS NUMBER) AS is_valid_member
      FROM base b
    UNION ALL
    SELECT 'DEDUP', NULL, r.pkey_trim, r.INDV_ID, r.SRC_TBL, r.CREATE_DT, r.DEATH_DT, NULL, NULL, r.RACE_CD,
           r.ETHNICITY_CD, r.src_full_name, r.std_first_name, r.std_mdl_name, r.std_lst_name, r.std_full_name,
           r.std_prfx_name, r.std_sfx_name, r.mdm_gender_code, NULL, NULL, NULL, r.std_birth_date, NULL, NULL, NULL,
           NULL, r.race_mstr, r.race_exception_code, r.race_exception_desc, r.race_exception_type, r.ethnicity_mstr,
           r.ethnicity_exception_code, r.ethnicity_exception_desc, r.ethnicity_exception_type, NULL, NULL, NULL,
           NULL, NULL, NULL, NULL, r.rn_pty, r.is_valid_member
      FROM dedup_ranked r;
    sp_ors_helper02_common(c_mapping, 'insert (C_S_TRS_PTY, C_S_TRS_PTY_RLE, STG_TRS_VALID_MEMBERS, exceptions)',
                           SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing;
/
