--------------------------------------------------------------------------------------------------------------------
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1
--
-- Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Deactivation_1 (workflow
-- wf_TRS_Stage_Load_1_Ongoing).
--
-- Processes TIERS members that were deactivated or deleted, as the first part of soft-deleting them in the MDM:
--   Read_STG_TRS_D_DC_INDV_and_CV (custom SQL): valid members (STG_TRS_VALID_MEMBERS) whose individual is inactive or
--     deleted in STG_TRS_D_DC_INDV, or inactive in STG_TRS_D_CV_DC_MCI_INDV
--   -> Delete_Valid_Stage (DD_DELETE)  -> STG_TRS_VALID_MEMBERS rows with that PTY_PK deleted (NOT performed)
--   -> Lookup_STG_TRS_DEACTIVED_MEMBERS + Filt_New_Only (not logged yet)
--        -> STG_TRS_DEACTIVED_MEMBERS (PROCESSED_YN 'N', LOAD_DATE = run start)
-- A later process sends the unprocessed keys to the MDM.
--
-- VALIDATION: none (no rule runs here).
-- BAD DATA: STG_TRS_DEACTIVED_MEMBERS has primary key INDV_ID, which Snowflake does not enforce. An individual can be
--   a valid member under two party keys (INDV_ID|DC_INDV and INDV_ID for MCI); IDQ writes the first and the database
--   rejects the second. Reproduced: one row per INDV_ID, and ids already in the table are skipped.
-- TIMELINE: none.
--
-- Not performed: the IDQ DD_DELETE of STG_TRS_VALID_MEMBERS. Insert only, so deactivated members stay in the valid
-- list (gathered-kb-todos-and-improvements-002.md N5 / D12).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1 ()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    c_mapping  VARCHAR DEFAULT 'm_Tgt_C_S_TRS_Pty_Deactivation_1';
    l_run_ts   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;   -- $sys.MappingRunStartTime
    l_rows     NUMBER DEFAULT 0;
    l_line     VARCHAR;
BEGIN
    BEGIN TRANSACTION;

    -- Filt_New_Only -> Write_STG_TRS_DEACTIVED_MEMBERS
    INSERT INTO STG_TRS_DEACTIVED_MEMBERS
           (INDV_ID, PTY_PK, SRC_TBL, CREATE_DATE, SRC_DEACTIVATION_DATE, LOAD_DATE, INACTIVE_IND, DELETE_SW,
            PROCESSED_YN)
    WITH deactv AS (
        SELECT indv_id, inactive_ind, delete_sw, create_dt
          FROM STG_TRS_D_DC_INDV
         WHERE inactive_ind = 'Y' OR delete_sw = 'Y'
        UNION ALL
        SELECT indv_id, inactive_ind, NULL, create_dt
          FROM STG_TRS_D_CV_DC_MCI_INDV
         WHERE inactive_ind = 'Y'
    ), deactv_id AS (
        SELECT indv_id, MAX(inactive_ind) inactive_ind, MAX(delete_sw) delete_sw, MIN(create_dt) src_deactivation_date
          FROM deactv
         GROUP BY indv_id
    )
    SELECT vm.INDV_ID, vm.PTY_PK, vm.SRC_TBL, vm.CREATE_DATE, d.src_deactivation_date, :l_run_ts, d.inactive_ind,
           d.delete_sw, 'N'
      FROM STG_TRS_VALID_MEMBERS vm
      JOIN deactv_id d ON d.indv_id = vm.indv_id
      -- Lookup_STG_TRS_DEACTIVED_MEMBERS + Filt_New_Only: ISNULL(PTY_PK1)
      LEFT JOIN (SELECT DISTINCT PTY_PK FROM STG_TRS_DEACTIVED_MEMBERS WHERE PTY_PK IS NOT NULL) dm
             ON dm.PTY_PK = vm.PTY_PK
      /* BAD DATA: primary key INDV_ID not yet in the table */
      LEFT JOIN (SELECT DISTINCT INDV_ID FROM STG_TRS_DEACTIVED_MEMBERS) di ON di.INDV_ID = vm.INDV_ID
     WHERE dm.PTY_PK IS NULL
       AND di.INDV_ID IS NULL
    /* BAD DATA: first row per INDV_ID in this run */
    QUALIFY ROW_NUMBER() OVER (PARTITION BY vm.INDV_ID ORDER BY vm.CREATE_DATE, vm.PTY_PK) = 1;
    l_rows := SQLROWCOUNT;
    SELECT fn_snow_helper36_common(:c_mapping, 'insert STG_TRS_DEACTIVED_MEMBERS', :l_rows) INTO :l_line;

    -- Delete_Valid_Stage (DD_DELETE) -> Write_STG_TRS_VALID_MEMBERS (key PTY_PK)
    -- Not performed: the IDQ DD_DELETE of STG_TRS_VALID_MEMBERS. This code base never deletes, truncates or drops (rows are only inserted).

    COMMIT;
    RETURN l_line;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
