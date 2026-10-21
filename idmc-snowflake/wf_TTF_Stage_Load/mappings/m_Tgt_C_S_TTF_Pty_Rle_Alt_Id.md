# m_Tgt_C_S_TTF_Pty_Rle_Alt_Id &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id`

Workflow `wf_TTF_Stage_Load`, step 3 of 4 in [`run_wf_TTF_Stage_Load.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/run_wf_TTF_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql); IDQ / CDI spec [`idmc/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md`](../../../idmc/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md); business description [`docs/mappings/027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md`](../../../docs/mappings/027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id`](../../../idq-to-oracle/wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Rle_Alt_Id (workflow wf_TTF_Stage_Load).

One alternate id per active TTF client into C_S_TTF_PTY_RLE_ALT_ID (insert only, never truncated): the party key
itself, type '024'.
  Read_V_TTF_ETL_SRC -> Filter: party not in STG_TTF_PTY_INACTIVE_STS -> target
```

## Validations

```text
VALIDATION: none (no rule runs here).
```

## Bad data

```text
BAD DATA: the source read stores a SQL text that is only a WHERE fragment (test client ids) and is not in
  custom-query mode: it is not applied. C_S_TTF_PTY_RLE_ALT_ID is unique on (PKEY_SRC_OBJECT, VERSION_SEQ), which
  Snowflake does not enforce: one row per key, keys already in the table skipped.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = run start ($sys.MappingRunStartTime).
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_TTF_PTY_RLE_ALT_ID` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
