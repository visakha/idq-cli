--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (workflow
-- wf_ECI_Stage_Load).
--
-- Meant to move the latest history row of each Medicaid record of a reactivated child (V_ECI_ETL_LU_REACTIVATED_ID,
-- ID_CHILD, via STG_ECI_SN_CASE) from STG_ECI_H_MEDICAID into the delta table STG_ECI_D_MEDICAID:
--   Read_STG_ECI_H_MEDICAID (source filter: latest LOAD_DATE per ID_MEDICAID of reactivated children)
--     -> Lookup_STG_ECI_D_MEDICAID (returns lkp_ID_MEDICAID)
--     -> Filt_Keep_New_Medicaid: IsNull(ID_MEDICAID)
--     -> Write_STG_ECI_D_MEDICAID (insert, no truncate)
--
-- IDQ DEFECT CARRIED OVER (docs/common_insights.md 1.2): the filter tests the SOURCE port ID_MEDICAID, not the
-- lookup result lkp_ID_MEDICAID. ID_MEDICAID is the history key and never NULL, so IDQ writes no rows. The default
-- reproduces that; P_TEST_LOOKUP_RESULT => 'Y' keeps the records not yet in STG_ECI_D_MEDICAID (intended behaviour,
-- as m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr / _Phn do).
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: STG_ECI_D_MEDICAID has primary key ID_MEDICAID, which Snowflake does not enforce: with 'Y', one row per
--   ID_MEDICAID is written and ids already in the table are skipped (IDQ would get the duplicate rejected).
-- TIMELINE: none.
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (
    P_TEST_LOOKUP_RESULT VARCHAR DEFAULT 'N'   -- 'N' = exactly as IDQ (defect), 'Y' = test lkp_ID_MEDICAID
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid';
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;
    INSERT INTO STG_ECI_D_MEDICAID
           (ID_MEDICAID, ID_CASE, MEDICAID_NBR, ELIG_DATE, END_DATE, CURRENT_IND, CANCEL_DATE, HMO_DESC,
            DATE_CREATED, DATE_MODIFIED, MODIFIED_BY, CREATED_BY, CONSENT_TO_BILL, LOAD_DATE)
    SELECT h.ID_MEDICAID, h.ID_CASE, h.MEDICAID_NBR, h.ELIG_DATE, h.END_DATE, h.CURRENT_IND, h.CANCEL_DATE,
           h.HMO_DESC, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CONSENT_TO_BILL, h.LOAD_DATE
      FROM STG_ECI_H_MEDICAID h
     -- Read_STG_ECI_H_MEDICAID source filter: (ID_MEDICAID, LOAD_DATE) IN (latest per Medicaid record)
     INNER JOIN (SELECT m.ID_MEDICAID, MAX(m.LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_MEDICAID m
                  INNER JOIN STG_ECI_SN_CASE c ON m.ID_CASE = c.ID_CASE
                  WHERE c.ID_CHILD IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_CHILD')
                  GROUP BY m.ID_MEDICAID) mx
             ON mx.ID_MEDICAID = h.ID_MEDICAID AND mx.MAX_LOAD_DATE = h.LOAD_DATE
     -- Lookup_STG_ECI_D_MEDICAID
      LEFT JOIN (SELECT DISTINCT ID_MEDICAID FROM STG_ECI_D_MEDICAID) d ON d.ID_MEDICAID = h.ID_MEDICAID
     -- Filt_Keep_New_Medicaid: 'Y' tests lkp_ID_MEDICAID; IDQ tests IsNull(ID_MEDICAID) on the source port
     WHERE IFF(:P_TEST_LOOKUP_RESULT = 'Y', d.ID_MEDICAID IS NULL, h.ID_MEDICAID IS NULL)
    /* BAD DATA: primary key ID_MEDICAID, first row per id in this run */
    QUALIFY ROW_NUMBER() OVER (PARTITION BY h.ID_MEDICAID ORDER BY h.DATE_MODIFIED DESC NULLS LAST) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert STG_ECI_D_MEDICAID', :l_rows) INTO :l_line;
    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
