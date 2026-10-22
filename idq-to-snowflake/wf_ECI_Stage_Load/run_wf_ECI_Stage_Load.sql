--------------------------------------------------------------------------------------------------------------------
-- run_wf_ECI_Stage_Load.sql - runs the Snowflake procedures that replace IDQ workflow wf_ECI_Stage_Load, in taskflow
-- order (docs-from-idq-exports/wf_ECI_Stage_Load/taskflow.md). The IDQ workflow runs some mappings in parallel; here they run one after
-- another, keeping every dependency of the taskflow. Each procedure is one transaction (COMMIT at the end, ROLLBACK
-- and re-raise on error); exit_on_error stops the run at the first failure, as the IDQ workflow does.
-- The IDQ command task (touch ${var:sys.WorkflowName}.ind on the DIS host) is not part of the database run: create
-- the indicator file from the scheduler after this script succeeds.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_ECI_Stage_Load.sql
-- The CLI (etl_process=SNOWFLAKE_SP) reads the CALL lines below: keep one "CALL sp_snow_main_<mapping>();" per line.
--------------------------------------------------------------------------------------------------------------------
!set exit_on_error=true

CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation();
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty();
CALL sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr();
CALL sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn();
CALL sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid();
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id();
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr();
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr();
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel();
