# wf_TTF_Stage_Load &rarr; Snowflake

The Snowflake stored procedures that replace the IDQ workflow `docs/wf_TTF_Stage_Load.xml`, in the order of [`run_wf_TTF_Stage_Load.sql`](../../idq-to-snowflake/wf_TTF_Stage_Load/run_wf_TTF_Stage_Load.sql) (the taskflow order of [`docs-from-idq-exports/wf_TTF_Stage_Load/taskflow.md`](../../docs-from-idq-exports/wf_TTF_Stage_Load/taskflow.md); parallel IDQ paths run one after another).

| Step | Mapping | Procedure |
|---|---|---|
| 1 | [`m_Tgt_C_S_TTF_Pty_Validation`](mappings/m_Tgt_C_S_TTF_Pty_Validation.md) | [`sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation`](../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql) |
| 2 | [`m_Tgt_C_S_TTF_Pty`](mappings/m_Tgt_C_S_TTF_Pty.md) | [`sp_snow_main_m_Tgt_C_S_TTF_Pty`](../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty.sql) |
| 3 | [`m_Tgt_C_S_TTF_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md) | [`sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id`](../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql) |
| 4 | [`m_Tgt_C_S_TTF_Pty_Rle_Phn`](mappings/m_Tgt_C_S_TTF_Pty_Rle_Phn.md) | [`sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn`](../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql) |

Conventions, install and the shared functions: [idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).
