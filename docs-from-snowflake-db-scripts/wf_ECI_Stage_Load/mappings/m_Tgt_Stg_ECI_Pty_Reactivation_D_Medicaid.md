# m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid &rarr; Snowflake `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`

Workflow `wf_ECI_Stage_Load`, step 5 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.md); Oracle port [`sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (workflow
wf_ECI_Stage_Load).

Meant to move the latest history row of each Medicaid record of a reactivated child (V_ECI_ETL_LU_REACTIVATED_ID,
ID_CHILD, via STG_ECI_SN_CASE) from STG_ECI_H_MEDICAID into the delta table STG_ECI_D_MEDICAID:
  Read_STG_ECI_H_MEDICAID (source filter: latest LOAD_DATE per ID_MEDICAID of reactivated children)
    -> Lookup_STG_ECI_D_MEDICAID (returns lkp_ID_MEDICAID)
    -> Filt_Keep_New_Medicaid: IsNull(ID_MEDICAID)
    -> Write_STG_ECI_D_MEDICAID (insert, no truncate)

IDQ DEFECT CARRIED OVER (docs/common_insights.md 1.2): the filter tests the SOURCE port ID_MEDICAID, not the
lookup result lkp_ID_MEDICAID. ID_MEDICAID is the history key and never NULL, so IDQ writes no rows. The default
reproduces that; P_TEST_LOOKUP_RESULT => 'Y' keeps the records not yet in STG_ECI_D_MEDICAID (intended behaviour,
as m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr / _Phn do).
```

## Validations

```text
VALIDATION: none (no rule runs here).
```

## Bad data

```text
BAD DATA: STG_ECI_D_MEDICAID has primary key ID_MEDICAID, which Snowflake does not enforce: with 'Y', one row per
  ID_MEDICAID is written and ids already in the table are skipped (IDQ would get the duplicate rejected).
```

## MDM timeline

```text
TIMELINE: none.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_TEST_LOOKUP_RESULT` | VARCHAR | `'N'` | 'N' = exactly as IDQ (defect), 'Y' = test lkp_ID_MEDICAID |

## Tables written (insert only)

| Table |
|---|
| `STG_ECI_D_MEDICAID` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
