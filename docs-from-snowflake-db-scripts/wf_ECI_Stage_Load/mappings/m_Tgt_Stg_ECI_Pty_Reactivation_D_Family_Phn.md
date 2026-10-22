# m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn &rarr; Snowflake `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`

Workflow `wf_ECI_Stage_Load`, step 4 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.md); Oracle port [`sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn (workflow
wf_ECI_Stage_Load).

Moves the latest history row of each phone record of a reactivated family (V_ECI_ETL_LU_REACTIVATED_ID,
ID_FAMILY) from STG_ECI_H_FAMILY_PHONE into the delta table STG_ECI_D_FAMILY_PHONE:
  Read_STG_ECI_H_FAMILY_PHONE (source filter: latest LOAD_DATE per ID_FAMILY_PHONE of reactivated families)
    -> Lookup_STG_ECI_D_FAMILY_PHONE -> Filt_Keep_New_Phone: phone record not already in the delta table
    -> Write_STG_ECI_D_FAMILY_PHONE (insert, no truncate)
```

## Validations

```text
VALIDATION: none (no rule runs here).
```

## Bad data

```text
BAD DATA: none; rows already in the delta table are skipped (Filt_Keep_New_Phone).
```

## MDM timeline

```text
TIMELINE: none.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `STG_ECI_D_FAMILY_PHONE` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
