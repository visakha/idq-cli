--------------------------------------------------------------------------------------------------------------------
-- run_wf_TRS_Stage_Load_1_Ongoing.sql - runs the Snowflake procedures that replace IDQ workflow
-- wf_TRS_Stage_Load_1_Ongoing, in taskflow order (idmc/wf_TRS_Stage_Load_1_Ongoing/taskflow.md). Parallel paths of
-- the IDQ workflow run one after another here, keeping every dependency:
--   * m_Tgt_C_S_TRS_Pty_OnGoing first (it builds STG_TRS_VALID_MEMBERS, which every later mapping joins to);
--   * m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw before m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (the second appends to the
--     table the first loads);
--   * m_Tgt_C_S_TRS_Addr_1 before m_Tgt_C_S_TRS_Addr_2 (part 2 reads the unique addresses of part 1).
-- Each procedure is one transaction; exit_on_error stops the run at the first failure.
-- The IDQ command task (touch <workflow>.ind) is left to the scheduler.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_TRS_Stage_Load_1_Ongoing.sql
-- The CLI (etl_process=SNOWFLAKE_SP) reads the CALL lines below: keep one "CALL sp_snow_main_<mapping>();" per line.
--------------------------------------------------------------------------------------------------------------------
!set exit_on_error=true

CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id();
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln();
CALL sp_snow_main_m_Tgt_C_S_TRS_Addr_1();
CALL sp_snow_main_m_Tgt_C_S_TRS_Addr_2();
