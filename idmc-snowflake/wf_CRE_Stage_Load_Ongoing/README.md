# wf_CRE_Stage_Load_Ongoing &rarr; Snowflake

The Snowflake stored procedures that replace the IDQ workflow `docs/wf_CRE_Stage_Load_Ongoing.xml`, in the order of [`run_wf_CRE_Stage_Load_Ongoing.sql`](../../idq-to-snowflake/wf_CRE_Stage_Load_Ongoing/run_wf_CRE_Stage_Load_Ongoing.sql) (the taskflow order of [`idmc/wf_CRE_Stage_Load_Ongoing/taskflow.md`](../../idmc/wf_CRE_Stage_Load_Ongoing/taskflow.md); parallel IDQ paths run one after another).

| Step | Mapping | Procedure |
|---|---|---|
| 1 | [`m_Tgt_C_S_CRE_CARE_Clients`](mappings/m_Tgt_C_S_CRE_CARE_Clients.md) | [`sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients`](../../idq-to-snowflake/wf_CRE_Stage_Load_Ongoing/sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql) |

Conventions, install and the shared functions: [idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).
