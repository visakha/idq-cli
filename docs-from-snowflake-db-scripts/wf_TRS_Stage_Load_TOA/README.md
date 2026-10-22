# wf_TRS_Stage_Load_TOA &rarr; Snowflake

The Snowflake stored procedures that replace the IDQ workflow `docs/wf_TRS_Stage_Load_TOA.xml`, in the order of [`run_wf_TRS_Stage_Load_TOA.sql`](../../idq-to-snowflake/wf_TRS_Stage_Load_TOA/run_wf_TRS_Stage_Load_TOA.sql) (the taskflow order of [`docs-from-idq-exports/wf_TRS_Stage_Load_TOA/taskflow.md`](../../docs-from-idq-exports/wf_TRS_Stage_Load_TOA/taskflow.md); parallel IDQ paths run one after another).

| Step | Mapping | Procedure |
|---|---|---|
| 1 | [`m_Tgt_C_S_TRS_Stg_TOA`](mappings/m_Tgt_C_S_TRS_Stg_TOA.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA`](../../idq-to-snowflake/wf_TRS_Stage_Load_TOA/sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA.sql) |

Conventions, install and the shared functions: [idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).
