--------------------------------------------------------------------------------------------------------------------
-- run_wf_TRS_Stage_Load_TOA.sql - runs the Snowflake procedure that replaces IDQ workflow
-- wf_TRS_Stage_Load_TOA (docs-from-idq-exports/wf_TRS_Stage_Load_TOA/taskflow.md: one mapping task, no command task).
-- The daily parent workflow runs it after run_wf_TRS_Stage_Load_1_Ongoing.sql; the CLI runs both for source TRS.
-- The procedure is one transaction; exit_on_error stops the run at a failure.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_TRS_Stage_Load_TOA.sql
-- The CLI (etl_process=SNOWFLAKE_SP) reads the CALL lines below: keep one "CALL sp_snow_main_<mapping>();" per line.
--------------------------------------------------------------------------------------------------------------------
!set exit_on_error=true

CALL sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA();
