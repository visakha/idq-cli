--------------------------------------------------------------------------------------------------------------------
-- sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1
--
-- Drop-in replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Deactivation_1 (workflow wf_TRS_Stage_Load_1_Ongoing).
--
-- Processes TIERS members that were deactivated or deleted, as the first part of soft-deleting them in the MDM:
--   Read_STG_TRS_D_DC_INDV_and_CV (custom SQL): valid members (STG_TRS_VALID_MEMBERS) whose individual is inactive or
--     deleted in STG_TRS_D_DC_INDV, or inactive in STG_TRS_D_CV_DC_MCI_INDV
--   -> Delete_Valid_Stage (DD_DELETE)  -> STG_TRS_VALID_MEMBERS rows with that PTY_PK deleted
--   -> Lookup_STG_TRS_DEACTIVED_MEMBERS + Filt_New_Only (not logged yet)
--        -> STG_TRS_DEACTIVED_MEMBERS (PROCESSED_YN 'N', LOAD_DATE = run start)
-- A later process sends the unprocessed keys to the MDM.
--
-- Timeline: none.
-- Order: the insert runs first; the delete removes the same members (its subquery reads STG_TRS_VALID_MEMBERS in its
-- own consistent snapshot, which still holds them).
--------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1
IS
    c_mapping  CONSTANT VARCHAR2(100) := 'm_Tgt_C_S_TRS_Pty_Deactivation_1';
    l_run_ts   TIMESTAMP := SYSTIMESTAMP;   -- $sys.MappingRunStartTime
BEGIN
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
    SELECT vm.INDV_ID, vm.PTY_PK, vm.SRC_TBL, vm.CREATE_DATE, d.src_deactivation_date, l_run_ts, d.inactive_ind,
           d.delete_sw, 'N'
      FROM STG_TRS_VALID_MEMBERS vm
      JOIN deactv_id d ON d.indv_id = vm.indv_id
     -- Lookup_STG_TRS_DEACTIVED_MEMBERS + Filt_New_Only: ISNULL(PTY_PK1)
     WHERE NOT EXISTS (SELECT 1 FROM STG_TRS_DEACTIVED_MEMBERS dm
                        WHERE dm.PTY_PK = vm.PTY_PK AND dm.PTY_PK IS NOT NULL);
    sp_ors_helper02_common(c_mapping, 'insert STG_TRS_DEACTIVED_MEMBERS', SQL%ROWCOUNT);

    -- Delete_Valid_Stage (DD_DELETE) -> Write_STG_TRS_VALID_MEMBERS (key PTY_PK)
    -- Not performed: the IDQ DD_DELETE of STG_TRS_VALID_MEMBERS. This code base never deletes, truncates or drops (rows are only inserted).
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1;
/
