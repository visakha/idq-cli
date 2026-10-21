# wf_WIC_Stage_Load &rarr; Snowflake

The Snowflake stored procedures that replace the IDQ workflow `docs/wf_WIC_Stage_Load.xml`, in the order of [`run_wf_WIC_Stage_Load.sql`](../../idq-to-snowflake/wf_WIC_Stage_Load/run_wf_WIC_Stage_Load.sql) (the taskflow order of [`idmc/wf_WIC_Stage_Load/taskflow.md`](../../idmc/wf_WIC_Stage_Load/taskflow.md); parallel IDQ paths run one after another).

| Step | Mapping | Procedure |
|---|---|---|
| 1 | [`m_Tgt_C_S_WIC_Pty_Validation`](mappings/m_Tgt_C_S_WIC_Pty_Validation.md) | [`sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation`](../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql) |
| 2 | [`m_Tgt_C_S_WIC_Pty`](mappings/m_Tgt_C_S_WIC_Pty.md) | [`sp_snow_main_m_Tgt_C_S_WIC_Pty`](../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty.sql) |
| 3 | [`m_Tgt_C_S_WIC_Pty_Addr`](mappings/m_Tgt_C_S_WIC_Pty_Addr.md) | [`sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr`](../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql) |
| 4 | [`m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md) | [`sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`](../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql) |
| 5 | [`m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md) | [`sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`](../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql) |

Conventions, install and the shared functions: [idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).
