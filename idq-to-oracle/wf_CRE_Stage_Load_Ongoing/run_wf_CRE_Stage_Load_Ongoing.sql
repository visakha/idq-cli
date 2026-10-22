--------------------------------------------------------------------------------------------------------------------
-- run_wf_CRE_Stage_Load_Ongoing.sql - runs the procedure that replaces IDQ workflow wf_CRE_Stage_Load_Ongoing
-- (idmc/wf_CRE_Stage_Load_Ongoing/taskflow.md: one mapping task, then the command task). The procedure commits;
-- WHENEVER SQLERROR stops the run at a failure, as the IDQ workflow does.
-- The IDQ command task (touch ${var:sys.WorkflowName}.ind on the DIS host) is not part of the database run: create the
-- indicator file from the scheduler after this script succeeds.
--------------------------------------------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET SERVEROUTPUT ON SIZE UNLIMITED

EXEC sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients
