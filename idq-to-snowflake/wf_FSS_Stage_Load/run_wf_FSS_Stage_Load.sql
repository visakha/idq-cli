--------------------------------------------------------------------------------------------------------------------
-- run_wf_FSS_Stage_Load.sql - runs the Snowflake procedures that replace IDQ workflow wf_FSS_Stage_Load, in taskflow
-- order (idmc/wf_FSS_Stage_Load/taskflow.md). Parallel paths of the IDQ workflow run one after another here, keeping
-- every dependency. Each procedure is one transaction; exit_on_error stops the run at the first failure.
-- The IDQ command task (touch <workflow>.ind) is left to the scheduler.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_FSS_Stage_Load.sql
-- The CLI (etl_process=SNOWFLAKE_SP) reads the CALL lines below: keep one "CALL sp_snow_main_<mapping>();" per line.
--------------------------------------------------------------------------------------------------------------------
!set exit_on_error=true

CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation();
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty();
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr();
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id();
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr();
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel();
