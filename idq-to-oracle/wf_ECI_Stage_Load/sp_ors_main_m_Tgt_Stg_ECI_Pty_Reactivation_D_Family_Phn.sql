--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
--
-- Drop-in replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn (workflow wf_ECI_Stage_Load).
--
-- Moves the latest history row of each phone record of a reactivated family (V_ECI_ETL_LU_REACTIVATED_ID,
-- ID_FAMILY) from STG_ECI_H_FAMILY_PHONE into the delta table STG_ECI_D_FAMILY_PHONE:
--   Read_STG_ECI_H_FAMILY_PHONE (source filter: latest LOAD_DATE per ID_FAMILY_PHONE of reactivated families)
--     -> Lookup_STG_ECI_D_FAMILY_PHONE -> Filt_Keep_New_Phone: phone record not already in the delta table
--     -> Write_STG_ECI_D_FAMILY_PHONE (insert, no truncate)
--
-- Timeline: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn';
BEGIN
    INSERT INTO STG_ECI_D_FAMILY_PHONE
           (ID_FAMILY_PHONE, ID_FAMILY, ID_CASE, HOME_AC, HOME_NBR, WORK_AC, WORK_NBR, WORK_EXT, CELL_AC, CELL_NBR,
            FAX_AC, FAX_NBR, PAGER_AC, PAGER_NBR, OTHER_AC, OTHER_NBR, EMAIL_ADDRESS, DATE_CREATED, DATE_MODIFIED,
            MODIFIED_BY, CREATED_BY, CHILD_RESIDES_IND, INACTIVE_IND, PRIMARY_CONTACT_IND, LOAD_DATE)
    SELECT h.ID_FAMILY_PHONE, h.ID_FAMILY, h.ID_CASE, h.HOME_AC, h.HOME_NBR, h.WORK_AC, h.WORK_NBR, h.WORK_EXT,
           h.CELL_AC, h.CELL_NBR, h.FAX_AC, h.FAX_NBR, h.PAGER_AC, h.PAGER_NBR, h.OTHER_AC, h.OTHER_NBR,
           h.EMAIL_ADDRESS, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CHILD_RESIDES_IND,
           h.INACTIVE_IND, h.PRIMARY_CONTACT_IND, h.LOAD_DATE
      FROM STG_ECI_H_FAMILY_PHONE h
     -- Read_STG_ECI_H_FAMILY_PHONE source filter
     WHERE (h.ID_FAMILY_PHONE, h.LOAD_DATE) IN
           (SELECT ID_FAMILY_PHONE, MAX(LOAD_DATE)
              FROM STG_ECI_H_FAMILY_PHONE
             WHERE ID_FAMILY IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_FAMILY')
             GROUP BY ID_FAMILY_PHONE)
       -- Lookup_STG_ECI_D_FAMILY_PHONE + Filt_Keep_New_Phone: IsNull(lkp_ID_FAMILY_PHONE)
       AND NOT EXISTS (SELECT 1 FROM STG_ECI_D_FAMILY_PHONE d
                        WHERE d.ID_FAMILY_PHONE = h.ID_FAMILY_PHONE AND d.ID_FAMILY_PHONE IS NOT NULL);
    sp_ors_helper02_common(c_mapping, 'insert STG_ECI_D_FAMILY_PHONE', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn;
/
