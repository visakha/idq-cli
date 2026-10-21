--------------------------------------------------------------------------------------------------------------------
-- install.sql - SnowSQL install of the IDQ -> Snowflake functions and stored procedures. Run it from this folder,
-- with the database and schema that hold (or see) the staging, MDM and reference tables as the current ones:
--
--     cd idq-to-snowflake
--     snowsql -c <connection> -d <database> -s <schema> -f install.sql
--
-- Order matters for the functions: a SQL UDF is validated when it is created, so every function it calls (and every
-- table a lookup function reads) must exist first. Procedures are compiled when they run.
--   1. common/01_snow_common_functions.sql  the mapplets / rules and IDQ helpers (fn_snow_helper01..36_common)
--   2. common/02_snow_common_lookups.sql    the reference lookups (fn_snow_helper40..47_common)
--   3. per workflow: mapping helpers (fn_snow_helper01_<mapping>), then every sp_snow_main_<mapping>
-- Nothing here deletes, truncates or drops; CREATE OR REPLACE only replaces these functions and procedures.
--------------------------------------------------------------------------------------------------------------------
!set exit_on_error=true
!set variable_substitution=false

!source common/01_snow_common_functions.sql
!source common/02_snow_common_lookups.sql

-- wf_ECI_Stage_Load
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql
!source wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql

-- wf_FSS_Stage_Load
!source wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql
!source wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty.sql
!source wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr.sql
!source wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.sql
!source wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql
!source wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql

-- wf_TRS_Stage_Load_1_Ongoing (mapping helpers first)
!source wf_TRS_Stage_Load_1_Ongoing/fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql
!source wf_TRS_Stage_Load_1_Ongoing/fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Addr_1.sql
!source wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Addr_2.sql

-- wf_TTF_Stage_Load
!source wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql
!source wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty.sql
!source wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql
!source wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql

-- wf_WIC_Stage_Load
!source wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql
!source wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty.sql
!source wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql
!source wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql
!source wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql

-- what was installed
SHOW USER FUNCTIONS LIKE 'FN_SNOW_HELPER%';
SHOW PROCEDURES LIKE 'SP_SNOW_MAIN_%';
