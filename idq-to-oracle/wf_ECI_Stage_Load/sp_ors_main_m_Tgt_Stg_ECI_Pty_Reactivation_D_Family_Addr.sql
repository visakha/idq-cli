--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr
--
-- Drop-in replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr (workflow wf_ECI_Stage_Load).
--
-- Moves the latest history row of each address of a reactivated family (V_ECI_ETL_LU_REACTIVATED_ID, ID_FAMILY)
-- from STG_ECI_H_FAMILY_ADDRESS into the delta table STG_ECI_D_FAMILY_ADDRESS, so the address mapping re-sends it
-- to the MDM with hub state 1:
--   Read_STG_ECI_H_FAMILY_ADDRESS (source filter: latest LOAD_DATE per ID_FAMILY_ADDRESS of reactivated families)
--     -> Lookup_STG_ECI_D_FAMILY_ADDRESS -> Filt_Keep_New_Addr: address not already in the delta table
--     -> Write_STG_ECI_D_FAMILY_ADDRESS (insert, no truncate)
--
-- Timeline: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr';
BEGIN
    INSERT INTO STG_ECI_D_FAMILY_ADDRESS
           (ID_FAMILY_ADDRESS, ID_FAMILY, ID_CASE, ADDRESS_CD, ADDRESS1, ADDRESS2, ID_ST_CITY_CNTY_ZIP, CITY_NAME,
            COUNTY_NAME, ZIP_CODE, ZIP_SFX, STATE_ABBREV, CANCEL_DATE, DATE_CREATED, DATE_MODIFIED, MODIFIED_BY,
            CREATED_BY, LOAD_DATE)
    SELECT h.ID_FAMILY_ADDRESS, h.ID_FAMILY, h.ID_CASE, h.ADDRESS_CD, h.ADDRESS1, h.ADDRESS2, h.ID_ST_CITY_CNTY_ZIP,
           h.CITY_NAME, h.COUNTY_NAME, h.ZIP_CODE, h.ZIP_SFX, h.STATE_ABBREV, h.CANCEL_DATE, h.DATE_CREATED,
           h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.LOAD_DATE
      FROM STG_ECI_H_FAMILY_ADDRESS h
     -- Read_STG_ECI_H_FAMILY_ADDRESS source filter
     WHERE (h.ID_FAMILY_ADDRESS, h.LOAD_DATE) IN
           (SELECT ID_FAMILY_ADDRESS, MAX(LOAD_DATE)
              FROM STG_ECI_H_FAMILY_ADDRESS
             WHERE ID_FAMILY IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_FAMILY')
             GROUP BY ID_FAMILY_ADDRESS)
       -- Lookup_STG_ECI_D_FAMILY_ADDRESS + Filt_Keep_New_Addr: IsNull(LKP_ID_FAMILY_ADDRESS)
       AND NOT EXISTS (SELECT 1 FROM STG_ECI_D_FAMILY_ADDRESS d
                        WHERE d.ID_FAMILY_ADDRESS = h.ID_FAMILY_ADDRESS AND d.ID_FAMILY_ADDRESS IS NOT NULL);
    sp_ors_helper02_common(c_mapping, 'insert STG_ECI_D_FAMILY_ADDRESS', SQL%ROWCOUNT);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr;
/
