--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Validation (workflow wf_WIC_Stage_Load, first step).
--
-- Checks the WIC parties (V_WIC_ETL_SRC) and maintains the deactivation list used by every later WIC mapping:
--   * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank      -> EXC_STG_BAD_REC_MEMB
--   * Rtr_Valid_Party.Deactivation       : the same condition
--                                          -> STG_WIC_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_WIC_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
--   * Rtr_Valid_Party.Reactivation       : has a status and both names present
--                                          -> STG_WIC_PTY_INACTIVE_LOG ('Reactivation')
--                                          -> STG_WIC_PTY_INACTIVE_STS row deleted (Upd_Delete_Inactive DD_DELETE)
--   * Default group: not linked.
--
-- Timeline: none.
-- Snapshot: all routing happens in one multi-table INSERT (read-consistent, lookups see the pre-run status); the
-- DELETE then removes exactly the keys logged as 'Reactivation' in this run.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_WIC_Pty_Validation';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime / SYSTIMESTAMP()
BEGIN
    INSERT ALL
        -- Write_Invalid_Party_Name
        WHEN name_missing = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, FIRST_NAME, MIDDLE_NAME,
                  LAST_NAME, RUN_DATE, SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE,
                  BIRTH_DATE)
            VALUES (DATEKEY, c_mapping, exc_attribute_name, exc_attribute_value, std_first_name, std_mdl_name,
                    std_lst_name, l_run_ts, 'WIC', PTY_SRC_KEY, fn_ors_helper04_common(exc_code_name),
                    fn_ors_helper05_common(exc_code_name), exc_code_name, DOB)
        -- Write_Deactv_STG_WIC_PTY_INACTIVE_LOG
        WHEN name_missing = 1 THEN
            INTO STG_WIC_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (PTY_SRC_KEY, 'WIC', 'Deactivation', l_run_ts)
        -- Filt_new_deactivations -> Write_new_STG_WIC_PTY_INACTIVE_STS
        WHEN name_missing = 1 AND deactivation_sts IS NULL THEN
            INTO STG_WIC_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (PTY_SRC_KEY, 'WIC', fn_ors_helper02_common(hub_state_ind), l_run_ts)
        -- Write_STG_WIC_PTY_INACTIVE_LOG (reactivation)
        WHEN deactivation_sts IS NOT NULL AND name_missing = 0 THEN
            INTO STG_WIC_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (PTY_SRC_KEY, 'WIC', 'Reactivation', l_run_ts)
    WITH
    enriched AS (
        SELECT /*+ NO_MERGE */
               v.SOURCE_TABLE, v.ID, v.FIRST_NAME, v.LAST_NAME, v.MIDDLE_NAME, v.DOB, v.DATEKEY, v.LOAD_DATE,
               v.PTY_SRC_KEY,
               sts.DEACTIVATION_STS AS deactivation_sts,
               xref.HUB_STATE_IND   AS hub_state_ind,
               fn_dq_std_name_indv_member(v.FIRST_NAME, v.MIDDLE_NAME, v.LAST_NAME,
                   LTRIM(RTRIM(v.FIRST_NAME || CASE WHEN v.MIDDLE_NAME IS NOT NULL THEN ' ' || LTRIM(RTRIM(v.MIDDLE_NAME)) END
                               || ' ' || LTRIM(v.LAST_NAME))),
                   NULL, NULL, NULL, NULL, 'WIC') AS nm
          FROM V_WIC_ETL_SRC v
         -- Lookup_STG_WIC_PTY_INACTIVE_STS
         OUTER APPLY (SELECT i.DEACTIVATION_STS FROM STG_WIC_PTY_INACTIVE_STS i
                       WHERE i.ROWID_SYSTEM = 'WIC' AND i.SRC_KEY = v.PTY_SRC_KEY
                       FETCH FIRST 1 ROW ONLY) sts
         -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'WIC')
         OUTER APPLY (SELECT x.HUB_STATE_IND FROM C_B_PTY_XREF x
                       WHERE x.ROWID_SYSTEM = 'WIC' AND x.PKEY_SRC_OBJECT = v.PTY_SRC_KEY
                       FETCH FIRST 1 ROW ONLY) xref
    ),
    named AS (
        SELECT n.*,
               n.nm.first_name AS std_first_name,
               n.nm.mdl_name   AS std_mdl_name,
               n.nm.lst_name   AS std_lst_name,
               CASE WHEN RTRIM(n.nm.first_name) IS NULL OR RTRIM(n.nm.lst_name) IS NULL THEN 1 ELSE 0 END AS name_missing
          FROM enriched n
    )
    -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
    SELECT r.*,
           CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'Missing_First_Name'
                WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Missing_Last_Name' END  AS exc_code_name,
           CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'First Name'
                WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Last Name' END          AS exc_attribute_name,
           CASE WHEN RTRIM(r.std_first_name) IS NULL THEN r.std_first_name
                WHEN RTRIM(r.std_lst_name) IS NULL THEN r.std_lst_name END       AS exc_attribute_value
      FROM named r;
    sp_ors_helper02_common(c_mapping, 'insert (exceptions, deactivation log/status, reactivation log)', SQL%ROWCOUNT);

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_WIC_PTY_INACTIVE_STS
    -- Not performed: the IDQ DD_DELETE of STG_WIC_PTY_INACTIVE_STS. This code base never deletes, truncates or drops (rows are only inserted).
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation;
/
