--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TTF_Pty_Validation
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Validation (workflow wf_TTF_Stage_Load, first step).
--
-- Checks the TTF clients (V_TTF_ETL_SRC) and maintains the deactivation list used by every later TTF mapping. Party
-- key = LPAD(CLIENTS_ID, 10, '0'). Names are standardized with CopyOf_mplt_Name_Standardization_Indv_Member
-- (fn_dq_std_name_indv_member; the TTF copy is identical apart from its name).
--   * Rtr_Valid_Party.Invalid_Party_Name : first or last name blank, or 'DECLINED' / 'DO_NOT_DISCLOSE'
--                                          -> EXC_STG_BAD_REC_MEMB (code Missing_/Invalid_First_/Last_Name)
--   * Rtr_Valid_Party.Deactivation       : name blank or 'DECLINED' (not 'DO_NOT_DISCLOSE'), or
--                                          CLIENT_EXISTS_FLAG = 'N'
--                                          -> STG_TTF_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_TTF_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
--   * Rtr_Valid_Party.Reactivation       : has a status, names present and not 'DECLINED', CLIENT_EXISTS_FLAG = 'Y'
--                                          -> STG_TTF_PTY_INACTIVE_LOG ('Reactivation')
--                                          -> STG_TTF_PTY_INACTIVE_STS row deleted (Upd_Delete_Inactive DD_DELETE)
--   * Default group: not linked.
-- The source read stores a SQL text that is only a WHERE fragment (test client ids) and is not in custom-query mode:
-- it is not applied. The C_B_PTY_XREF lookup filter is TRIM(ROWID_SYSTEM) = 'TTF' (the MDM column is blank padded).
--
-- Timeline: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TTF_Pty_Validation
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TTF_Pty_Validation';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
BEGIN
    INSERT ALL
        -- Write_Invalid_Party_Name
        WHEN grp_invalid_party_name = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, RUN_DATE,
                  SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE, BIRTH_DATE, ATTRIBUTE_VALUE)
            VALUES (CREATEDDATE, c_mapping, exc_code_name /* ATTRIBUTE_NAME_Name has the same expression */,
                    std_first_name, std_mdl_name, std_lst_name, l_run_ts, 'TTF', pkey_src_object,
                    fn_ors_helper04_common(exc_code_name), fn_ors_helper05_common(exc_code_name), exc_code_name, DOB,
                    std_src_full_name)
        -- Write_STG_TTF_PTY_INACTIVE_LOG (Exp_Log_Deactv)
        WHEN grp_deactivation = 1 THEN
            INTO STG_TTF_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, 'TTF', 'Deactivation', l_run_ts)
        -- Filt_new_deactivations -> Write_STG_TTF_PTY_INACTIVE_STS2
        WHEN grp_deactivation = 1 AND deactivation_sts IS NULL THEN
            INTO STG_TTF_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (pkey_src_object, 'TTF', fn_ors_helper02_common(hub_state_ind), l_run_ts)
        -- Write_STG_TTF_PTY_INACTIVE_LOG1 (Exp_Log_Reactv)
        WHEN grp_reactivation = 1 THEN
            INTO STG_TTF_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, 'TTF', 'Reactivation', l_run_ts)
    WITH
    enriched AS (
        SELECT /*+ NO_MERGE */
               v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.CREATEDDATE, v.SUBMITDATE,
               v.CLIENT_EXISTS_FLAG,
               LPAD(v.CLIENTS_ID, 10, '0')  AS pkey_src_object,
               sts.DEACTIVATION_STS         AS deactivation_sts,
               xref.HUB_STATE_IND           AS hub_state_ind,
               fn_dq_std_name_indv_member(v.FIRSTNAME, v.MIDDLENAME, v.LASTNAME,
                   LTRIM(RTRIM(v.FIRSTNAME || CASE WHEN v.MIDDLENAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(v.MIDDLENAME)) END
                               || ' ' || LTRIM(v.LASTNAME))),
                   NULL, NULL, NULL, NULL, 'TTF') AS nm
          FROM V_TTF_ETL_SRC v
         -- Lookup_STG_TTF_PTY_INACTIVE_STS
         OUTER APPLY (SELECT i.DEACTIVATION_STS FROM STG_TTF_PTY_INACTIVE_STS i
                       WHERE i.SRC_KEY = LPAD(v.CLIENTS_ID, 10, '0') AND i.ROWID_SYSTEM = 'TTF'
                       FETCH FIRST 1 ROW ONLY) sts
         -- Lookup_C_B_PTY_XREF (lookup filter TRIM(ROWID_SYSTEM) = 'TTF')
         OUTER APPLY (SELECT x.HUB_STATE_IND FROM C_B_PTY_XREF x
                       WHERE TRIM(x.ROWID_SYSTEM) = 'TTF' AND x.PKEY_SRC_OBJECT = LPAD(v.CLIENTS_ID, 10, '0')
                       FETCH FIRST 1 ROW ONLY) xref
    ),
    named AS (
        SELECT n.*,
               n.nm.first_name    AS std_first_name,
               n.nm.mdl_name      AS std_mdl_name,
               n.nm.lst_name      AS std_lst_name,
               n.nm.src_full_name AS std_src_full_name,
               CASE WHEN RTRIM(n.nm.first_name) IS NULL OR RTRIM(n.nm.lst_name) IS NULL THEN 1 ELSE 0 END AS name_missing,
               CASE WHEN UPPER(n.nm.lst_name) = 'DECLINED' OR UPPER(n.nm.first_name) = 'DECLINED'
                    THEN 1 ELSE 0 END                                                               AS name_declined,
               CASE WHEN UPPER(n.nm.lst_name) = 'DO_NOT_DISCLOSE' OR UPPER(n.nm.first_name) = 'DO_NOT_DISCLOSE'
                    THEN 1 ELSE 0 END                                                               AS name_undisclosed
          FROM enriched n
    )
    -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
    SELECT r.*,
           CASE WHEN r.name_missing = 1 OR r.name_declined = 1 OR r.name_undisclosed = 1
                THEN 1 ELSE 0 END                                                          AS grp_invalid_party_name,
           CASE WHEN r.name_missing = 1 OR r.name_declined = 1 OR r.CLIENT_EXISTS_FLAG = 'N'
                THEN 1 ELSE 0 END                                                          AS grp_deactivation,
           CASE WHEN r.deactivation_sts IS NOT NULL AND r.name_missing = 0
                     AND NOT (UPPER(r.std_lst_name) = 'DECLINED') AND NOT (UPPER(r.std_first_name) = 'DECLINED')
                     AND r.CLIENT_EXISTS_FLAG = 'Y'
                THEN 1 ELSE 0 END                                                          AS grp_reactivation,
           CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'Missing_First_Name'
                WHEN UPPER(LTRIM(RTRIM(r.std_first_name))) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_First_Name'
                WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Missing_Last_Name'
                WHEN UPPER(LTRIM(RTRIM(r.std_lst_name))) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_Last_Name'
                ELSE 'Valid' END                                                           AS exc_code_name
      FROM named r;
    sp_ors_helper02_common(c_mapping, 'insert (exceptions, deactivation log/status, reactivation log)', SQL%ROWCOUNT);

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_TTF_PTY_INACTIVE_STS1
    DELETE FROM STG_TTF_PTY_INACTIVE_STS t
     WHERE (t.SRC_KEY, t.ROWID_SYSTEM) IN (SELECT l.SRC_KEY, l.ROWID_SYSTEM
                                             FROM STG_TTF_PTY_INACTIVE_LOG l
                                            WHERE l.ACTION = 'Reactivation'
                                              AND l.ACTION_DT = l_run_ts);
    sp_ors_helper02_common(c_mapping, 'delete STG_TTF_PTY_INACTIVE_STS (reactivations)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TTF_Pty_Validation;
/
