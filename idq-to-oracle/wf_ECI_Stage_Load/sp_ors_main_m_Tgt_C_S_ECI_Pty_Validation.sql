--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Validation (workflow wf_ECI_Stage_Load, first step).
--
-- Checks every ECI child and family party of the delta (STG_ECI_D_CHILD + STG_ECI_D_FAMILY) and maintains the
-- deactivation list that every later ECI mapping uses as a filter:
--   * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank (and the family is not already
--                                          inactive)                     -> EXC_STG_BAD_REC_MEMB
--   * Rtr_Valid_Party.Deactivation       : name blank, or a duplicate case (V_ECI_ETL_LU_DUP_CASES), or the family is
--                                          inactive (V_ECI_ETL_LU_FAMILY_VALIDATION)
--                                          -> STG_ECI_PTY_INACTIVE_LOG ('Deactivation')
--                                          -> STG_ECI_PTY_INACTIVE_STS (new row, only when the party has no status yet;
--                                             H / D / P from the C_B_PTY_XREF hub state)
--   * Rtr_Valid_Party.Reactivation       : party has a status, names present, not a duplicate, family active
--                                          -> STG_ECI_PTY_INACTIVE_LOG ('Reactivation')
--                                          -> STG_ECI_PTY_INACTIVE_STS row deleted (Upd_Delete_Inactive DD_DELETE)
--   * Default group                      : not linked, rows dropped.
-- A row goes to every group whose condition is true (IDQ router semantics), so Invalid_Party_Name rows are also
-- Deactivation rows.
--
-- Timeline: this mapping has no MDM timeline logic.
--
-- Snapshot: the lookups on STG_ECI_PTY_INACTIVE_STS read the table as it was before the run (IDQ static lookup
-- cache): all routing happens in one multi-table INSERT (one read-consistent statement). The DELETE that follows
-- removes exactly the keys that INSERT logged as 'Reactivation' in this run, so it does not re-evaluate anything.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_ECI_Pty_Validation';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- SYSTIMESTAMP() of RUN_DATE / DEACTIVATION_DT / ACTION_DT
BEGIN
    INSERT ALL
        -- Write_Invalid_Party_Name (Exp_Invalid_PTY_NM + Lkp_EXC_LOOKUP_CODE_VALUE_Name)
        WHEN grp_invalid_party_name = 1 THEN
            INTO EXC_STG_BAD_REC_MEMB
                 (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
                  FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
                  PERIOD_START_DATE)
            VALUES (src_system, pkey_src_object, exc_code_name, fn_ors_helper04_common(exc_code_name),
                    fn_ors_helper05_common(exc_code_name), l_run_ts,
                    std_first_name, std_mdl_name, std_lst_name, dob, exc_attribute_name, exc_attribute_value,
                    c_mapping, date_created)
        -- Write_Deactv_STG_ECI_PTY_INACTIVE_LOG (Exp_Log_Deactv)
        WHEN grp_deactivation = 1 THEN
            INTO STG_ECI_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, src_system, 'Deactivation', l_run_ts)
        -- Filt_new_deactivations: IsNull(DEACTIVATION_STS) -> Write_new_STG_ECI_PTY_INACTIVE_STS (Exp_New_Deactvn_Sts)
        WHEN grp_deactivation = 1 AND deactivation_sts IS NULL THEN
            INTO STG_ECI_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
            VALUES (pkey_src_object, src_system, fn_ors_helper02_common(hub_state_ind), l_run_ts)
        -- Write_STG_ECI_PTY_INACTIVE_LOG (Exp_Log_Reactv)
        WHEN grp_reactivation = 1 THEN
            INTO STG_ECI_PTY_INACTIVE_LOG (SRC_KEY, ROWID_SYSTEM, ACTION, ACTION_DT)
            VALUES (pkey_src_object, src_system, 'Reactivation', l_run_ts)
    WITH
    -- Read_STG_ECI_D_CHILD_and_FAMILY (custom SQL, query mode SEMI)
    src AS (
        SELECT 'ECI_CHILD' AS SOURCE_TABLE, c.ID_CHILD AS ID, c.FIRST_NAME, c.LAST_NAME, c.MIDDLE_INITIAL, c.DOB,
               c.DATE_CREATED, c.DATE_MODIFIED, c.MODIFIED_BY, c.CREATED_BY, c.LOAD_DATE
          FROM STG_ECI_D_CHILD c
        UNION ALL
        SELECT 'ECI_FAMILY' AS SOURCE_TABLE, fam.ID_FAMILY AS ID, fam.FIRST_NAME, fam.LAST_NAME, fam.MIDDLE_INITIAL,
               fam.DOB, fam.DATE_CREATED, fam.DATE_MODIFIED, fam.MODIFIED_BY, fam.CREATED_BY, fam.LOAD_DATE
          FROM STG_ECI_D_FAMILY fam
    ),
    -- Exp_ECI_Data_Load
    exp_load AS (
        SELECT s.*,
               LPAD(s.ID, 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' END  AS pkey_src_object,
               'ECI'                                                                        AS src_system,
               -- v_FULL_NAME is declared string(10) in IDQ, so the full name is cut at 10 characters; it only
               -- feeds the name mapplet, whose full-name outputs this mapping does not write.
               SUBSTR(LTRIM(RTRIM(s.FIRST_NAME
                      || CASE WHEN s.MIDDLE_INITIAL IS NOT NULL THEN ' ' || LTRIM(RTRIM(s.MIDDLE_INITIAL)) END
                      || ' ' || LTRIM(s.LAST_NAME))), 1, 10)                               AS full_name
          FROM src s
    ),
    -- lookups + mplt_Name_Standardization_Indv_Member
    enriched AS (
        SELECT /*+ NO_MERGE */
               e.*,
               sts.DEACTIVATION_STS                                                    AS deactivation_sts,
               xref.HUB_STATE_IND                                                      AS hub_state_ind,
               dup.ID                                                                  AS omit_id,
               CASE WHEN fam.FAM_NAME_STATUS IS NULL AND fam.FAM_PHONE_AND_ADDRESS_STS IS NULL
                         AND fam.FAM_INACTIVE_STS IS NULL THEN 'N' ELSE 'Y' END        AS fam_inactive_yn,
               fn_dq_std_name_indv_member(e.FIRST_NAME, e.MIDDLE_INITIAL, e.LAST_NAME, e.full_name,
                                          NULL, NULL, NULL, NULL, e.src_system)        AS nm
          FROM exp_load e
         -- Lookup_STG_ECI_PTY_INACTIVE_STS
         OUTER APPLY (SELECT i.DEACTIVATION_STS FROM STG_ECI_PTY_INACTIVE_STS i
                       WHERE i.SRC_KEY = e.pkey_src_object AND i.ROWID_SYSTEM = e.src_system
                       FETCH FIRST 1 ROW ONLY) sts
         -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'ECI')
         OUTER APPLY (SELECT x.HUB_STATE_IND FROM C_B_PTY_XREF x
                       WHERE x.ROWID_SYSTEM = 'ECI' AND x.PKEY_SRC_OBJECT = e.pkey_src_object
                       FETCH FIRST 1 ROW ONLY) xref
         -- Lookup_V_ECI_ETL_LU_DUP_CASES
         OUTER APPLY (SELECT d.ID FROM V_ECI_ETL_LU_DUP_CASES d
                       WHERE d.SOURCE_TABLE = e.SOURCE_TABLE AND d.ID = e.ID
                       FETCH FIRST 1 ROW ONLY) dup
         -- Lookup_V_ECI_ETL_LU_FAMILY_VALIDATION
         OUTER APPLY (SELECT f.FAM_NAME_STATUS, f.FAM_PHONE_AND_ADDRESS_STS, f.FAM_INACTIVE_STS
                        FROM V_ECI_ETL_LU_FAMILY_VALIDATION f
                       WHERE f.SOURCE_TABLE = e.SOURCE_TABLE AND f.ID_FAMILY = e.ID
                       FETCH FIRST 1 ROW ONLY) fam
    ),
    -- Exp_Consolidate_Exceptions + Rtr_Valid_Party conditions + Exp_Invalid_PTY_NM
    routed AS (
        SELECT r.*,
               CASE WHEN r.name_missing = 1 AND r.fam_inactive_yn = 'N' THEN 1 ELSE 0 END      AS grp_invalid_party_name,
               CASE WHEN r.name_missing = 1 OR r.omit_id IS NOT NULL OR r.fam_inactive_yn = 'Y'
                    THEN 1 ELSE 0 END                                                           AS grp_deactivation,
               CASE WHEN r.deactivation_sts IS NOT NULL AND r.name_missing = 0 AND r.omit_id IS NULL
                         AND r.fam_inactive_yn = 'N' THEN 1 ELSE 0 END                          AS grp_reactivation,
               CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'Missing_First_Name'
                    WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Missing_Last_Name' END             AS exc_code_name,
               CASE WHEN RTRIM(r.std_first_name) IS NULL THEN 'First Name'
                    WHEN RTRIM(r.std_lst_name) IS NULL THEN 'Last Name' END                     AS exc_attribute_name,
               CASE WHEN RTRIM(r.std_first_name) IS NULL THEN r.std_first_name
                    WHEN RTRIM(r.std_lst_name) IS NULL THEN r.std_lst_name END                  AS exc_attribute_value
          FROM (SELECT n.*,
                       n.nm.first_name AS std_first_name,
                       n.nm.mdl_name   AS std_mdl_name,
                       n.nm.lst_name   AS std_lst_name,
                       -- IDQ: Length(Rtrim(x)) = 0 OR IsNull(x)  ==  Oracle: RTRIM(x) IS NULL
                       CASE WHEN RTRIM(n.nm.first_name) IS NULL OR RTRIM(n.nm.lst_name) IS NULL
                            THEN 1 ELSE 0 END AS name_missing
                  FROM enriched n) r
    )
    SELECT * FROM routed;
    sp_ors_helper02_common(c_mapping, 'insert (exceptions, deactivation log/status, reactivation log)', SQL%ROWCOUNT);

    -- Rtr_Valid_Party.Reactivation -> Upd_Delete_Inactive (DD_DELETE) -> Write_STG_ECI_PTY_INACTIVE_STS.
    -- The Reactivation group was just logged with ACTION_DT = l_run_ts; those log rows are exactly the keys to delete.
    DELETE FROM STG_ECI_PTY_INACTIVE_STS t
     WHERE (t.SRC_KEY, t.ROWID_SYSTEM) IN (SELECT l.SRC_KEY, l.ROWID_SYSTEM
                                             FROM STG_ECI_PTY_INACTIVE_LOG l
                                            WHERE l.ACTION = 'Reactivation'
                                              AND l.ACTION_DT = l_run_ts);
    sp_ors_helper02_common(c_mapping, 'delete STG_ECI_PTY_INACTIVE_STS (reactivations)', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation;
/
