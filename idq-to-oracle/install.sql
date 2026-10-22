--------------------------------------------------------------------------------------------------------------------
-- install.sql - SQL*Plus / SQLcl install of the IDQ -> Oracle stored procedures (run from this folder).
--
-- Order: object types, (contract stubs), shared helpers, then one sp_ors_main_* per IDQ mapping.
-- 02_dq_functions_contract.sql is commented out: the fn_dq_* functions are assumed to exist. Uncomment it only in a
-- scratch schema to compile the procedures; its bodies raise ORA-20999 and would overwrite the real functions.
--------------------------------------------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET DEFINE OFF

@@common/01_dq_types.sql
-- @@common/02_dq_functions_contract.sql
@@common/03_ors_common_helpers.sql

-- wf_ECI_Stage_Load
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr.sql
@@wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql

-- wf_FSS_Stage_Load
@@wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation.sql
@@wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty.sql
@@wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr.sql
@@wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.sql
@@wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql
@@wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql

-- wf_TRS_Stage_Load_1_Ongoing
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Addr_1.sql
@@wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Addr_2.sql

-- wf_TTF_Stage_Load
@@wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty_Validation.sql
@@wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty.sql
@@wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql
@@wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql

-- wf_WIC_Stage_Load
@@wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation.sql
@@wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty.sql
@@wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty_Addr.sql
@@wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql
@@wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql

-- wf_CRE_Stage_Load_Ongoing
@@wf_CRE_Stage_Load_Ongoing/sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients.sql

-- wf_TRS_Stage_Load_TOA (TRS, run after wf_TRS_Stage_Load_1_Ongoing)
@@wf_TRS_Stage_Load_TOA/sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA.sql

SHOW ERRORS
SELECT object_type, object_name, status FROM user_objects
 WHERE (object_name LIKE 'SP\_ORS\_%' ESCAPE '\' OR object_name LIKE 'FN\_ORS\_%' ESCAPE '\'
        OR object_name LIKE 'FN\_DQ\_%' ESCAPE '\' OR object_name LIKE 'T\_DQ\_%' ESCAPE '\')
   AND status <> 'VALID';
