# m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 8 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql); IDQ / CDI spec [`idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md`](../../../idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md); business description [`docs/mappings/007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md`](../../../docs/mappings/007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw (workflow wf_TRS_Stage_Load_1_Ongoing).

Managed attributes ("switches") of the valid TIERS members into C_S_TRS_PTY_MNG_ATTR (insert only, never truncated):
  Read_Stg_TRS_D_DC_Indv (custom SQL: latest DC_INDV / MCI row per individual joined to STG_TRS_VALID_MEMBERS)
  -> exp_Attr_Type + nrm_Attribute_Types: one row per attribute (five UNION ALL branches here)
       File_Clearance_SW = FILE_CLEARANCE_SW, SSA_Validation_SW = SSA_VALIDATION_SW, TW_Convert_Ind,
       LTC_Convert_Ind, Source_Table = SRC_TBL
  -> fltr_Null_Values: value present and not blank
  -> exp_Pkey_Src_Object: key = PTY_PK || '|' || attribute type
  -> srtr_Pkey (distinct) -> exp_Version_Seq_No -> target
Runs BEFORE m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, which appends to the same table.
```

## Validations

```text
VALIDATION: none (no rule runs here).
```

## Bad data

```text
BAD DATA: NULL or blank switch values are dropped (fltr_Null_Values, IDQ blank test). Unfed ports written as NULL:
  ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND. C_S_TRS_PTY_MNG_ATTR is unique on
  (PKEY_SRC_OBJECT, VERSION_SEQ), which Snowflake does not enforce: one row per key, keys already there skipped.
```

## MDM timeline

```text
TIMELINE: exp_Version_Seq_No.VERSION_SEQ_NUM is hard-coded to 1 (the running version counter is commented out in
  IDQ); PERIOD_START_DATE = EFF_BEGIN_DT; PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION are linked to
  unfed ports (NULL).
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_TRS_PTY_MNG_ATTR` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper03_common` | IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) (BOOLEAN) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
