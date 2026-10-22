# m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr &rarr; Snowflake `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`

Workflow `wf_ECI_Stage_Load`, step 3 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.md); Oracle port [`sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr (workflow
wf_ECI_Stage_Load).

Moves the latest history row of each address of a reactivated family (V_ECI_ETL_LU_REACTIVATED_ID, ID_FAMILY)
from STG_ECI_H_FAMILY_ADDRESS into the delta table STG_ECI_D_FAMILY_ADDRESS, so the address mapping re-sends it
to the MDM with hub state 1:
  Read_STG_ECI_H_FAMILY_ADDRESS (source filter: latest LOAD_DATE per ID_FAMILY_ADDRESS of reactivated families)
    -> Lookup_STG_ECI_D_FAMILY_ADDRESS -> Filt_Keep_New_Addr: address not already in the delta table
    -> Write_STG_ECI_D_FAMILY_ADDRESS (insert, no truncate)
```

## Validations

```text
VALIDATION: none (no rule runs here).
```

## Bad data

```text
BAD DATA: none; rows already in the delta table are skipped (Filt_Keep_New_Addr); the lookup reads the table as it
  was before the insert.
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
| `STG_ECI_D_FAMILY_ADDRESS` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
