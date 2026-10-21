--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Nm (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Alias names of valid TIERS members (STG_TRS_D_CV_DC_MCI_ALIAS + STG_TRS_D_DC_ALIAS joined to STG_TRS_VALID_MEMBERS)
-- into C_S_TRS_PTY_NM (insert only, never truncated), name type '002' (Alias):
--   -> fltr_Null_Fn_Ln: source first and last name present
--   -> mplt_Name_Standardization_Trailing_Num_Removal (fn_snow_helper14_common) on the source names, then
--      mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common) on its output with the source prefix, suffix
--      and full name
--   -> srtr_Pkey (distinct) -> exp_Party_Consolidation -> srtr_TRS_Pty_Nm (distinct) -> exp_Pkey -> target
--      key = PKEY_PTY || '|002|' || SEQUENCE_NUM
--
-- VALIDATION: the name mapplets clean the names; the mapplet's source-system input is not linked in this mapping, so
--   its prefix / suffix lookups (keyed on the source system) never match: PFX_NM / SFX_NM are NULL.
-- BAD DATA: aliases without a first or last name are dropped (fltr_Null_Fn_Ln). Unfed ports written as NULL:
--   ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND. C_S_TRS_PTY_NM is unique on (PKEY_SRC_OBJECT,
--   VERSION_SEQ), which Snowflake does not enforce: when one alias key has several distinct versions IDQ keeps the
--   first that arrives and the database rejects the rest; here the latest CREATE_DT is kept, keys already in the
--   table are skipped.
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Party_Consolidation ranks versions per party (v_VERSION_SEQ_RANK, v_DUP_RANK) but VERSION_SEQ_NUM is
--     hard-coded to 1 (the rank is commented out) and DUP_RANK is not written.
--   * PERIOD_START_DATE_OUT = IIF(v_DUP_RANK = 1, PERIOD_START_DATE, v_LAST_STRT_DATE) is a carry-forward of the
--     version start date. IDQ evaluates variable ports before output ports; v_LAST_STRT_DATE is already set to the
--     current PERIOD_START_DATE, so the output is always the current row's CREATE_DT (docs/common_insights.md 6).
--   * PERIOD_END_DATE, PERIOD_REFERENCE_TIME are linked to unfed ports (NULL).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm (
    P_MEMBER_NAME_TYPE_CODE VARCHAR DEFAULT '002'   -- $MemberNameTypeCode
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Nm';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    -- Not performed: IDQ "truncate target table" of C_S_TRS_PTY_NM. This code base never deletes, truncates or drops (rows are only inserted).

    INSERT INTO C_S_TRS_PTY_NM
           (PTY_FK, SFX_NM, FRST_NM, PFX_NM, LST_NM, MDL_NM, FULL_NM, VERSION_SEQ, LAST_UPDATE_DATE, NM_TP, SRC_ROWID,
            ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_END_DATE, PERIOD_REFERENCE_TIME, UPDATED_BY,
            CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_FULL_NM, SRC_LAST_UPD_DT, PKEY_SRC_OBJECT, PERIOD_START_DATE)
    WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    -- Read_STG_TRS_D_CV_DC_MCI_Alias (custom SQL, query mode SEMI)
    src AS (
        SELECT DISTINCT DC_ALIAS.INDV_ID AS INDV_ID, DC_ALIAS.PKEY_PTY AS PKEY_PTY,
               RTRIM(LTRIM(DC_ALIAS.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(DC_ALIAS.MID_NAME)) AS MID_NAME,
               RTRIM(LTRIM(DC_ALIAS.LAST_NAME)) AS LAST_NAME, RTRIM(DC_ALIAS.SUFX_NAME) AS SUFX_NAME,
               RTRIM(DC_ALIAS.PREFIX_NAME) AS PREFIX_NAME, DC_ALIAS.CREATE_DT AS CREATE_DT,
               DC_ALIAS.SEQUENCE_NUM AS SEQUENCE_NUM
          FROM (SELECT INDV_ID, TO_VARCHAR(INDV_ID) AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME,
                       PREFIX_NAME, CREATE_DT, SEQUENCE_NUM
                  FROM STG_TRS_D_CV_DC_MCI_ALIAS MCI_ALIAS
                UNION ALL
                SELECT INDV_ID, TO_VARCHAR(INDV_ID) || '|DC_INDV' AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME,
                       SUFX_NAME, PREFIX_NAME, CREATE_DT, SEQ_NUM
                  FROM STG_TRS_D_DC_ALIAS DC_ALIAS) DC_ALIAS
          JOIN STG_TRS_VALID_MEMBERS VM ON DC_ALIAS.PKEY_PTY = VM.PTY_PK
    ),
    named AS (
        SELECT s.*,
               TRIM(NVL(s.FIRST_NAME, '') || IFF(s.MID_NAME IS NOT NULL, ' ' || TRIM(s.MID_NAME), '')
                    || ' ' || NVL(LTRIM(s.LAST_NAME), ''))                                   AS src_full_name,
               fn_snow_helper14_common(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME, NULL)          AS tn
          FROM src s
         WHERE s.FIRST_NAME IS NOT NULL AND s.LAST_NAME IS NOT NULL                         -- fltr_Null_Fn_Ln
    ),
    std AS (
        SELECT n.*,
               -- source system not linked: the prefix / suffix lookups cannot match (NULL standardized values)
               fn_snow_helper15_common(n.tn:first_name::VARCHAR, n.tn:middle_name::VARCHAR, n.tn:last_name::VARCHAR,
                                       n.src_full_name, n.PREFIX_NAME, n.SUFX_NAME, NULL, NULL,
                                       jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)            AS nm
          FROM named n
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(n.tn:first_name::VARCHAR)) AND jf.IS_FIRST_JUNK
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(n.tn:last_name::VARCHAR)) AND jl.IS_LAST_JUNK
    ),
    -- srtr_Pkey (distinct) / srtr_TRS_Pty_Nm (distinct); GNDR_CD is an unfed port (NULL) and is left out
    dedup AS (
        SELECT DISTINCT s.PKEY_PTY, s.CREATE_DT, s.nm:sfx_name::VARCHAR AS sfx_nm,
               s.nm:first_name::VARCHAR AS frst_nm, s.nm:prfx_name::VARCHAR AS prfx_nm,
               s.nm:last_name::VARCHAR AS lst_nm, s.nm:middle_name::VARCHAR AS mdl_nm,
               s.nm:full_name::VARCHAR AS full_nm, s.src_full_name, s.SEQUENCE_NUM,
               NVL(s.PKEY_PTY, '') || '|' || :P_MEMBER_NAME_TYPE_CODE || '|' || NVL(TO_VARCHAR(s.SEQUENCE_NUM), '')
                                                                                            AS pkey_src_object
          FROM std s
    )
    -- exp_Party_Consolidation + exp_Pkey
    SELECT d.PKEY_PTY, d.sfx_nm, d.frst_nm, d.prfx_nm, d.lst_nm, d.mdl_nm, d.full_nm,
           1 /* TIMELINE: VERSION_SEQ_NUM hard-coded */, :l_run_ts, :P_MEMBER_NAME_TYPE_CODE, d.pkey_src_object,
           NULL, NULL, NULL, NULL, NULL /* TIMELINE: unfed */, NULL /* TIMELINE: unfed */, NULL, d.CREATE_DT, NULL,
           NULL, d.src_full_name, d.CREATE_DT, d.pkey_src_object,
           d.CREATE_DT /* TIMELINE: PERIOD_START_DATE_OUT, see header */
      FROM dedup d
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_NM WHERE VERSION_SEQ = 1) xn
             ON xn.PKEY_SRC_OBJECT = d.pkey_src_object
     /* BAD DATA: unique key not yet in the table, first row per key in this run */
     WHERE xn.PKEY_SRC_OBJECT IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object ORDER BY d.CREATE_DT DESC NULLS LAST, d.full_nm) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert C_S_TRS_PTY_NM', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
