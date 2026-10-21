--------------------------------------------------------------------------------------------------------------------
-- run_wf_WIC_Stage_Load.sql - runs the procedures that replace IDQ workflow wf_WIC_Stage_Load, in taskflow order
-- (idmc/wf_WIC_Stage_Load/taskflow.md). The IDQ workflow runs some mappings in parallel; here they run one after another,
-- keeping every dependency of the taskflow (paths of a parallel step run one path after another). Each procedure commits;
-- WHENEVER SQLERROR stops the run at the first failure, as the IDQ workflow does.
-- The IDQ command task (touch ${var:sys.WorkflowName}.ind on the DIS host) is not part of the database run: create the
-- indicator file from the scheduler after this script succeeds.
--------------------------------------------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET SERVEROUTPUT ON SIZE UNLIMITED

EXEC sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation
EXEC sp_ors_main_m_Tgt_C_S_WIC_Pty
EXEC sp_ors_main_m_Tgt_C_S_WIC_Pty_Addr
EXEC sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr
EXEC sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id
