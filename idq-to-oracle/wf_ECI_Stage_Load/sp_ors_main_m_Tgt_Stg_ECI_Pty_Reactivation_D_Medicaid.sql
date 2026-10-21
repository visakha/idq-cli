--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid
--
-- Drop-in replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (workflow wf_ECI_Stage_Load).
--
-- Meant to move the latest history row of each Medicaid record of a reactivated child (V_ECI_ETL_LU_REACTIVATED_ID,
-- ID_CHILD, via STG_ECI_SN_CASE) from STG_ECI_H_MEDICAID into the delta table STG_ECI_D_MEDICAID:
--   Read_STG_ECI_H_MEDICAID (source filter: latest LOAD_DATE per ID_MEDICAID of reactivated children)
--     -> Lookup_STG_ECI_D_MEDICAID (returns lkp_ID_MEDICAID)
--     -> Filt_Keep_New_Medicaid: IsNull(ID_MEDICAID)
--     -> Write_STG_ECI_D_MEDICAID (insert, no truncate)
--
-- IDQ DEFECT CARRIED OVER: the filter tests the SOURCE port ID_MEDICAID, not the lookup result lkp_ID_MEDICAID (the
-- sister mappings test the lookup result). ID_MEDICAID is the history key and never NULL, so IDQ writes no rows.
-- This procedure reproduces that. To get the intended behaviour, call it with p_test_lookup_result => 'Y', which
-- keeps the records not yet in STG_ECI_D_MEDICAID (as m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr / _Phn do).
--
-- Timeline: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (
    p_test_lookup_result  IN VARCHAR2 DEFAULT 'N'   -- 'N' = exactly as IDQ (defect), 'Y' = test lkp_ID_MEDICAID
)
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid';
BEGIN
    INSERT INTO STG_ECI_D_MEDICAID
           (ID_MEDICAID, ID_CASE, MEDICAID_NBR, ELIG_DATE, END_DATE, CURRENT_IND, CANCEL_DATE, HMO_DESC,
            DATE_CREATED, DATE_MODIFIED, MODIFIED_BY, CREATED_BY, CONSENT_TO_BILL, LOAD_DATE)
    SELECT h.ID_MEDICAID, h.ID_CASE, h.MEDICAID_NBR, h.ELIG_DATE, h.END_DATE, h.CURRENT_IND, h.CANCEL_DATE,
           h.HMO_DESC, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CONSENT_TO_BILL, h.LOAD_DATE
      FROM STG_ECI_H_MEDICAID h
     -- Read_STG_ECI_H_MEDICAID source filter
     WHERE (h.ID_MEDICAID, h.LOAD_DATE) IN
           (SELECT ID_MEDICAID, MAX(m.LOAD_DATE)
              FROM STG_ECI_H_MEDICAID m
             INNER JOIN STG_ECI_SN_CASE c ON m.ID_CASE = c.ID_CASE
             WHERE ID_CHILD IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_CHILD')
             GROUP BY ID_MEDICAID)
       -- Filt_Keep_New_Medicaid
       AND CASE WHEN p_test_lookup_result = 'Y'
                THEN CASE WHEN NOT EXISTS (SELECT 1 FROM STG_ECI_D_MEDICAID d
                                            WHERE d.ID_MEDICAID = h.ID_MEDICAID AND d.ID_MEDICAID IS NOT NULL)
                          THEN 1 ELSE 0 END
                ELSE CASE WHEN h.ID_MEDICAID IS NULL THEN 1 ELSE 0 END   -- IDQ: IsNull(ID_MEDICAID) on the source port
           END = 1;
    sp_ors_helper02_common(c_mapping, 'insert STG_ECI_D_MEDICAID', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid;
/
