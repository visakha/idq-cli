--------------------------------------------------------------------------------------------------------------------
-- run_wf_CRE_Stage_Load_Ongoing.sql - runs the Snowflake procedure that replaces IDQ workflow
-- wf_CRE_Stage_Load_Ongoing (docs-from-idq-exports/wf_CRE_Stage_Load_Ongoing/taskflow.md: one mapping task, then the command task).
-- The procedure is one transaction; exit_on_error stops the run at a failure.
-- The IDQ command task (touch <workflow>.ind) is left to the scheduler.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_CRE_Stage_Load_Ongoing.sql
-- The CLI (etl_process=SNOWFLAKE_SP) reads the CALL lines below: keep one "CALL sp_snow_main_<mapping>();" per line.
--------------------------------------------------------------------------------------------------------------------
!set exit_on_error=true

CALL sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients();
