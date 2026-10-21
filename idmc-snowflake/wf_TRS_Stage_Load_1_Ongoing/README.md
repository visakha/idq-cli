# wf_TRS_Stage_Load_1_Ongoing &rarr; Snowflake

The Snowflake stored procedures that replace the IDQ workflow `docs/wf_TRS_Stage_Load_1_Ongoing.xml`, in the order of [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql) (the taskflow order of [`idmc/wf_TRS_Stage_Load_1_Ongoing/taskflow.md`](../../idmc/wf_TRS_Stage_Load_1_Ongoing/taskflow.md); parallel IDQ paths run one after another).

| Step | Mapping | Procedure |
|---|---|---|
| 1 | [`m_Tgt_C_S_TRS_Pty_OnGoing`](mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql) |
| 2 | [`m_Tgt_C_S_TRS_Pty_Deactivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Deactivation_1.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql) |
| 3 | [`m_Tgt_C_S_TRS_Pty_Rle_TOA`](mappings/m_Tgt_C_S_TRS_Pty_Rle_TOA.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql) |
| 4 | [`m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql) |
| 5 | [`m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql) |
| 6 | [`m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql) |
| 7 | [`m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql) |
| 8 | [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql) |
| 9 | [`m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql) |
| 10 | [`m_Tgt_C_S_TRS_Pty_Nm`](mappings/m_Tgt_C_S_TRS_Pty_Nm.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql) |
| 11 | [`m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql) |
| 12 | [`m_Tgt_C_S_TRS_Pty_Rle_Pln`](mappings/m_Tgt_C_S_TRS_Pty_Rle_Pln.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql) |
| 13 | [`m_Tgt_C_S_TRS_Addr_1`](mappings/m_Tgt_C_S_TRS_Addr_1.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Addr_1`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Addr_1.sql) |
| 14 | [`m_Tgt_C_S_TRS_Addr_2`](mappings/m_Tgt_C_S_TRS_Addr_2.md) | [`sp_snow_main_m_Tgt_C_S_TRS_Addr_2`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Addr_2.sql) |

Mapping-specific helpers:

- [`fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql)
- [`fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql)

Conventions, install and the shared functions: [idq-to-snowflake/README.md](../../idq-to-snowflake/README.md).
