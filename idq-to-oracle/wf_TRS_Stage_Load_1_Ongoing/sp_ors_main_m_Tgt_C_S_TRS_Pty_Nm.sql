--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Nm (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Alias names of valid TIERS members (STG_TRS_D_CV_DC_MCI_ALIAS + STG_TRS_D_DC_ALIAS joined to STG_TRS_VALID_MEMBERS)
-- into C_S_TRS_PTY_NM (truncated first), name type '002' (Alias):
--   -> fltr_Null_Fn_Ln: source first and last name present
--   -> mplt_Name_Standardization_Trailing_Num_Removal (fn_dq_std_name_trailing_num) on the source names, then
--      mplt_Name_Standardization_Indv_Member (fn_dq_std_name_indv_member) on its output with the source prefix,
--      suffix and full name
--   -> srtr_Pkey (distinct) -> exp_Party_Consolidation -> srtr_TRS_Pty_Nm (distinct) -> exp_Pkey -> target
--      key = PKEY_PTY || '|002|' || SEQUENCE_NUM
--
-- TIMELINE (stale MDM timeline, ported as IDQ does it):
--   * exp_Party_Consolidation ranks versions per party (v_VERSION_SEQ_RANK, v_DUP_RANK) but VERSION_SEQ_NUM is
--     hard-coded to 1 (the rank is commented out) and DUP_RANK is not written.
--   * PERIOD_START_DATE_OUT = IIF(v_DUP_RANK = 1, PERIOD_START_DATE, v_LAST_STRT_DATE) is a carry-forward of the
--     version start date. IDQ evaluates input ports, then variable ports in display order, then output ports;
--     v_LAST_STRT_DATE (a variable, set to the current PERIOD_START_DATE) is evaluated BEFORE the output port, so the
--     output is always the current row's PERIOD_START_DATE (the alias CREATE_DT). That is what is written here.
--   * PERIOD_END_DATE, PERIOD_REFERENCE_TIME are linked to unfed ports (NULL).
--   * The second distinct sorter (srtr_TRS_Pty_Nm) adds DUP_RANK to the compared ports, but its input is already
--     distinct on all other ports, so one DISTINCT reproduces both sorters.
-- Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm (
    p_member_name_type_code  IN VARCHAR2 DEFAULT '002'   -- $MemberNameTypeCode
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Nm';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
    sp_ors_helper01_common('C_S_TRS_PTY_NM');

    INSERT INTO C_S_TRS_PTY_NM
           (PTY_FK, SFX_NM, FRST_NM, PFX_NM, LST_NM, MDL_NM, FULL_NM, VERSION_SEQ, LAST_UPDATE_DATE, NM_TP, SRC_ROWID,
            ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_END_DATE, PERIOD_REFERENCE_TIME, UPDATED_BY,
            CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_FULL_NM, SRC_LAST_UPD_DT, PKEY_SRC_OBJECT, PERIOD_START_DATE)
    WITH
    -- Read_STG_TRS_D_CV_DC_MCI_Alias (custom SQL, query mode SEMI) + fltr_Null_Fn_Ln
    src AS (
        SELECT DISTINCT DC_ALIAS.INDV_ID AS INDV_ID, DC_ALIAS.PKEY_PTY AS PKEY_PTY,
               RTRIM(LTRIM(DC_ALIAS.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(DC_ALIAS.MID_NAME)) AS MID_NAME,
               RTRIM(LTRIM(DC_ALIAS.LAST_NAME)) AS LAST_NAME, RTRIM(DC_ALIAS.SUFX_NAME) AS SUFX_NAME,
               RTRIM(DC_ALIAS.PREFIX_NAME) AS PREFIX_NAME, DC_ALIAS.CREATE_DT AS CREATE_DT,
               DC_ALIAS.SEQUENCE_NUM AS SEQUENCE_NUM
          FROM (SELECT INDV_ID, TO_CHAR(INDV_ID) AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME,
                       CREATE_DT, SEQUENCE_NUM
                  FROM STG_TRS_D_CV_DC_MCI_ALIAS MCI_ALIAS
                UNION ALL
                SELECT INDV_ID, TO_CHAR(INDV_ID) || '|DC_INDV' AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME,
                       PREFIX_NAME, CREATE_DT, SEQ_NUM
                  FROM STG_TRS_D_DC_ALIAS DC_ALIAS) DC_ALIAS
          JOIN STG_TRS_VALID_MEMBERS VM ON DC_ALIAS.PKEY_PTY = VM.PTY_PK
    ),
    named AS (
        SELECT /*+ NO_MERGE */
               s.*,
               LTRIM(RTRIM(s.FIRST_NAME || CASE WHEN s.MID_NAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(s.MID_NAME)) END
                           || ' ' || LTRIM(s.LAST_NAME)))                                     AS src_full_name,
               fn_dq_std_name_trailing_num(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME, NULL)       AS tn
          FROM src s
         WHERE s.FIRST_NAME IS NOT NULL AND s.LAST_NAME IS NOT NULL                          -- fltr_Null_Fn_Ln
    ),
    std AS (
        SELECT /*+ NO_MERGE */
               n.*,
               fn_dq_std_name_indv_member(n.tn.first_name, n.tn.middle_name, n.tn.last_name, n.src_full_name,
                                          n.PREFIX_NAME, n.SUFX_NAME, NULL, NULL, NULL)       AS nm
          FROM named n
    ),
    -- srtr_Pkey (distinct) / srtr_TRS_Pty_Nm (distinct); GNDR_CD is an unfed port (NULL) and is left out
    dedup AS (
        SELECT DISTINCT s.PKEY_PTY, s.CREATE_DT, s.nm.sfx_name AS sfx_nm, s.nm.first_name AS frst_nm,
               s.nm.prfx_name AS prfx_nm, s.nm.lst_name AS lst_nm, s.nm.mdl_name AS mdl_nm, s.nm.full_name AS full_nm,
               s.src_full_name, s.SEQUENCE_NUM
          FROM std s
    )
    -- exp_Party_Consolidation + exp_Pkey
    SELECT PKEY_PTY, sfx_nm, frst_nm, prfx_nm, lst_nm, mdl_nm, full_nm, 1 /* TIMELINE: VERSION_SEQ_NUM hard-coded */,
           l_run_ts, p_member_name_type_code,
           PKEY_PTY || '|' || p_member_name_type_code || '|' || TO_CHAR(SEQUENCE_NUM),
           NULL, NULL, NULL, NULL, NULL /* TIMELINE: unfed */, NULL /* TIMELINE: unfed */, NULL, CREATE_DT, NULL, NULL,
           src_full_name, CREATE_DT, PKEY_PTY || '|' || p_member_name_type_code || '|' || TO_CHAR(SEQUENCE_NUM),
           CREATE_DT /* TIMELINE: PERIOD_START_DATE_OUT, see header */
      FROM dedup;
    sp_ors_helper02_common(c_mapping, 'insert C_S_TRS_PTY_NM', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm;
/
