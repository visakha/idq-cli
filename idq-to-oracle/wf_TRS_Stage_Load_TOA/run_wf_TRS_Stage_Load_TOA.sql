--------------------------------------------------------------------------------------------------------------------
-- run_wf_TRS_Stage_Load_TOA.sql - runs the procedure that replaces IDQ workflow wf_TRS_Stage_Load_TOA
-- (docs-from-idq-exports/wf_TRS_Stage_Load_TOA/taskflow.md: one mapping task, no command task). The daily parent
-- workflow runs it after run_wf_TRS_Stage_Load_1_Ongoing.sql; the CLI runs both for source TRS. The procedure commits;
-- WHENEVER SQLERROR stops the run at a failure, as the IDQ workflow does.
--------------------------------------------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET SERVEROUTPUT ON SIZE UNLIMITED

EXEC sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA
