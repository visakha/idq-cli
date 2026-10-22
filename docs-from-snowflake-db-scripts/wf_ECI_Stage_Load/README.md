# wf_ECI_Stage_Load &rarr; Snowflake

The Snowflake stored procedures that replace the IDQ workflow `docs/wf_ECI_Stage_Load.xml`, in the order of [`run_wf_ECI_Stage_Load.sql`](../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql) (the taskflow order of [`docs-from-idq-exports/wf_ECI_Stage_Load/taskflow.md`](../../docs-from-idq-exports/wf_ECI_Stage_Load/taskflow.md); parallel IDQ paths run one after another).

| Step | Mapping | Procedure |
|---|---|---|
| 1 | [`m_Tgt_C_S_ECI_Pty_Validation`](mappings/m_Tgt_C_S_ECI_Pty_Validation.md) | [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation.sql) |
| 2 | [`m_Tgt_C_S_ECI_Pty`](mappings/m_Tgt_C_S_ECI_Pty.md) | [`sp_snow_main_m_Tgt_C_S_ECI_Pty`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty.sql) |
| 3 | [`m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`](mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.md) | [`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql) |
| 4 | [`m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`](mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.md) | [`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql) |
| 5 | [`m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`](mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.md) | [`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql) |
| 6 | [`m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md) | [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql) |
| 7 | [`m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md) | [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql) |
| 8 | [`m_Tgt_C_S_ECI_Pty_Addr`](mappings/m_Tgt_C_S_ECI_Pty_Addr.md) | [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql) |
| 9 | [`m_Tgt_C_S_ECI_Pty_Rle_Rel`](mappings/m_Tgt_C_S_ECI_Pty_Rle_Rel.md) | [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel`](../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql) |

Conventions, install and the shared functions: [idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).
