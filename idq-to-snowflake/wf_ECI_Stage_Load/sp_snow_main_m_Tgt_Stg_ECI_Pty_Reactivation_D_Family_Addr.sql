--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr (workflow
-- wf_ECI_Stage_Load).
--
-- Moves the latest history row of each address of a reactivated family (V_ECI_ETL_LU_REACTIVATED_ID, ID_FAMILY)
-- from STG_ECI_H_FAMILY_ADDRESS into the delta table STG_ECI_D_FAMILY_ADDRESS, so the address mapping re-sends it
-- to the MDM with hub state 1:
--   Read_STG_ECI_H_FAMILY_ADDRESS (source filter: latest LOAD_DATE per ID_FAMILY_ADDRESS of reactivated families)
--     -> Lookup_STG_ECI_D_FAMILY_ADDRESS -> Filt_Keep_New_Addr: address not already in the delta table
--     -> Write_STG_ECI_D_FAMILY_ADDRESS (insert, no truncate)
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: none; rows already in the delta table are skipped (Filt_Keep_New_Addr); the lookup reads the table as it
--   was before the insert.
-- TIMELINE: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr';
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    INSERT INTO STG_ECI_D_FAMILY_ADDRESS
           (ID_FAMILY_ADDRESS, ID_FAMILY, ID_CASE, ADDRESS_CD, ADDRESS1, ADDRESS2, ID_ST_CITY_CNTY_ZIP, CITY_NAME,
            COUNTY_NAME, ZIP_CODE, ZIP_SFX, STATE_ABBREV, CANCEL_DATE, DATE_CREATED, DATE_MODIFIED, MODIFIED_BY,
            CREATED_BY, LOAD_DATE)
    SELECT h.ID_FAMILY_ADDRESS, h.ID_FAMILY, h.ID_CASE, h.ADDRESS_CD, h.ADDRESS1, h.ADDRESS2, h.ID_ST_CITY_CNTY_ZIP,
           h.CITY_NAME, h.COUNTY_NAME, h.ZIP_CODE, h.ZIP_SFX, h.STATE_ABBREV, h.CANCEL_DATE, h.DATE_CREATED,
           h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.LOAD_DATE
      FROM STG_ECI_H_FAMILY_ADDRESS h
     -- Read_STG_ECI_H_FAMILY_ADDRESS source filter: (ID_FAMILY_ADDRESS, LOAD_DATE) IN (latest per address)
     INNER JOIN (SELECT ID_FAMILY_ADDRESS, MAX(LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_FAMILY_ADDRESS
                  WHERE ID_FAMILY IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_FAMILY')
                  GROUP BY ID_FAMILY_ADDRESS) m
             ON m.ID_FAMILY_ADDRESS = h.ID_FAMILY_ADDRESS AND m.MAX_LOAD_DATE = h.LOAD_DATE
     -- Lookup_STG_ECI_D_FAMILY_ADDRESS + Filt_Keep_New_Addr: IsNull(LKP_ID_FAMILY_ADDRESS)
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_D_FAMILY_ADDRESS d
                        WHERE d.ID_FAMILY_ADDRESS = h.ID_FAMILY_ADDRESS);
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert STG_ECI_D_FAMILY_ADDRESS', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
