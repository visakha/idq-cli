--------------------------------------------------------------------------------------------------------------------
-- run_wf_TRS_Stage_Load_1_Ongoing.sql - runs the procedures that replace IDQ workflow wf_TRS_Stage_Load_1_Ongoing, in taskflow order
-- (docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/taskflow.md). The IDQ workflow runs some mappings in parallel; here they run one after another,
-- keeping every dependency of the taskflow (paths of a parallel step run one path after another). Each procedure commits;
-- WHENEVER SQLERROR stops the run at the first failure, as the IDQ workflow does.
-- The IDQ command task (touch ${var:sys.WorkflowName}.ind on the DIS host) is not part of the database run: create the
-- indicator file from the scheduler after this script succeeds.
--------------------------------------------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET SERVEROUTPUT ON SIZE UNLIMITED

EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id
EXEC sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln
EXEC sp_ors_main_m_Tgt_C_S_TRS_Addr_1
EXEC sp_ors_main_m_Tgt_C_S_TRS_Addr_2
