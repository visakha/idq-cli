--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Validation (workflow wf_FSS_Stage_Load, first step).
--
-- Checks the FSS clients (V_FSS_ETL_SRC, rows that are the last active registration of a client or that mark all
-- registrations inactive) and maintains the deactivation list used by every later FSS mapping:
--   * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank      -> EXC_STG_BAD_REC_MEMB
--   * Rtr_Valid_Party.Deactivation       : name blank, client deleted (CLIENT_DTL__CAPXACTION = 'D') or all
--                                          registrations inactive (LAST_INACTV_CLIENT_YN = 'Y')
--                                          -> STG_FSS_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_FSS_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
--   * Rtr_Valid_Party.Reactivation       : has a status, names present, not deleted, not all inactive
--                                          -> STG_FSS_PTY_INACTIVE_STS rows of the key deleted (Upd_Delete_Inactive)
--                                          -> STG_FSS_PTY_INACTIVE_STS row inserted with DEACTIVATION_STS =
--                                             'Reactivation' (IDQ links Exp_Log_Reactv to the STATUS table, not the
--                                             log; ported as observed, see docs/mappings/019). Because later mappings
--                                             skip any key with a non-null status, a reactivated FSS client stays
--                                             excluded - confirm with the business.
--   * Default group: not linked.
-- NULL capture action / inactive flag: "x <> 'D'" is not true for NULL in IDQ or Oracle, so such rows are not
-- reactivated.
--
-- Timeline: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_FSS_Pty_Validation';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
BEGIN
    INSERT ALL
        -- Write_Invalid_Party_Name
        WHEN grp_invalid_party_name = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, RUN_DATE,
                  SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE, BIRTH_DATE, ATTRIBUTE_VALUE)
            VALUES (DT_LAST_UPDATE, c_mapping, exc_attribute_name, std_first_name, std_mdl_name, std_lst_name,
                    l_run_ts, 'FSS', PTY_SRC_KEY, fn_ors_helper04_common(exc_code_name),
                    fn_ors_helper05_common(exc_code_name), exc_code_name, DT_DOB, std_src_full_name)
        -- Write_STG_FSS_PTY_INACTIVE_LOG (Exp_Log_Deactv)
        WHEN grp_deactivation = 1 THEN
            INTO STG_FSS_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (PTY_SRC_KEY, 'FSS', 'Deactivation', l_run_ts)
        -- Filt_new_deactivations -> Write_STG_FSS_PTY_INACTIVE_STS2 (Exp_New_Deactvn_Sts)
        WHEN grp_deactivation = 1 AND deactivation_sts IS NULL THEN
            INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (PTY_SRC_KEY, 'FSS', fn_ors_helper02_common(hub_state_ind), l_run_ts)
        -- Write_STG_FSS_PTY_INACTIVE_STS (Exp_Log_Reactv: ACTION -> DEACTIVATION_STS, ACTION_DT -> DEACTIVATION_DT)
        WHEN grp_reactivation = 1 THEN
            INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (PTY_SRC_KEY, 'FSS', 'Reactivation', l_run_ts)
    WITH
    -- Read_V_FSS_ETL_SRC (source filter; the commented-out testing filters are not applied)
    src AS (
        SELECT v.ID_CLIENT, v.PTY_SRC_KEY, v.SOURCE_TYPE, v.NM_FIRST, v.NM_LAST, v.NM_MIDDLE, v.DT_DOB,
               v.DT_LAST_UPDATE, v.CLIENT_DTL__CAPXACTION, v.STG_UPDATE_DATE, v.LAST_INACTV_CLIENT_YN
          FROM V_FSS_ETL_SRC v
         WHERE (v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y' OR v.LAST_INACTV_CLIENT_YN = 'Y')
    ),
    -- Exp_ECI_Data_Load (sic) + lookups + mplt_Name_Standardization_Indv_Member
    enriched AS (
        SELECT /*+ NO_MERGE */
               s.*,
               sts.DEACTIVATION_STS AS deactivation_sts,
               xref.HUB_STATE_IND   AS hub_state_ind,
               fn_dq_std_name_indv_member(s.NM_FIRST, s.NM_MIDDLE, s.NM_LAST,
                   LTRIM(RTRIM(s.NM_FIRST || CASE WHEN s.NM_MIDDLE IS NOT NULL THEN ' ' || LTRIM(RTRIM(s.NM_MIDDLE)) END
                               || ' ' || LTRIM(s.NM_LAST))),
                   NULL, NULL, NULL, NULL, 'FSS') AS nm
          FROM src s
         -- Lookup_STG_FSS_PTY_INACTIVE_STS
         OUTER APPLY (SELECT i.DEACTIVATION_STS FROM STG_FSS_PTY_INACTIVE_STS i
                       WHERE i.SRC_KEY = s.PTY_SRC_KEY AND i.ROWID_SYSTEM = 'FSS'
                       FETCH FIRST 1 ROW ONLY) sts
         -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'FSS')
         OUTER APPLY (SELECT x.HUB_STATE_IND FROM C_B_PTY_XREF x
                       WHERE x.ROWID_SYSTEM = 'FSS' AND x.PKEY_SRC_OBJECT = s.PTY_SRC_KEY
                       FETCH FIRST 1 ROW ONLY) xref
    ),
    named AS (
        SELECT n.*,
               n.nm.first_name    AS std_first_name,
               n.nm.mdl_name      AS std_mdl_name,
               n.nm.lst_name      AS std_lst_name,
               n.nm.src_full_name AS std_src_full_name,
               CASE WHEN RTRIM(n.nm.first_name) IS NULL OR RTRIM(n.nm.lst_name) IS NULL THEN 1 ELSE 0 END AS name_missing
          FROM enriched n
    )
    -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
    SELECT r.*,
           r.name_missing                                                                  AS grp_invalid_party_name,
           CASE WHEN r.name_missing = 1 OR r.CLIENT_DTL__CAPXACTION = 'D' OR r.LAST_INACTV_CLIENT_YN = 'Y'
                THEN 1 ELSE 0 END                                                          AS grp_deactivation,
           CASE WHEN r.deactivation_sts IS NOT NULL AND r.name_missing = 0
                     AND r.CLIENT_DTL__CAPXACTION <> 'D' AND r.LAST_INACTV_CLIENT_YN <> 'Y'
                THEN 1 ELSE 0 END                                                          AS grp_reactivation,
           CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'Missing_First_Name'
                WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Missing_Last_Name' END            AS exc_code_name,
           CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'First Name'
                WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Last Name' END                    AS exc_attribute_name
      FROM named r;
    sp_ors_helper02_common(c_mapping, 'insert (exceptions, log, statuses)', SQL%ROWCOUNT);

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_FSS_PTY_INACTIVE_STS1:
    -- delete the earlier status rows of every key that was just given a 'Reactivation' status row.
    -- Not performed: the IDQ DD_DELETE of STG_FSS_PTY_INACTIVE_STS. This code base never deletes, truncates or drops (rows are only inserted).
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation;
/
