# m_Tgt_C_S_TRS_Pty_Deactivation_1 &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 2 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Deactivation_1.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Deactivation_1.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Deactivation_1 (workflow
wf_TRS_Stage_Load_1_Ongoing).

Processes TIERS members that were deactivated or deleted, as the first part of soft-deleting them in the MDM:
  Read_STG_TRS_D_DC_INDV_and_CV (custom SQL): valid members (STG_TRS_VALID_MEMBERS) whose individual is inactive or
    deleted in STG_TRS_D_DC_INDV, or inactive in STG_TRS_D_CV_DC_MCI_INDV
  -> Delete_Valid_Stage (DD_DELETE)  -> STG_TRS_VALID_MEMBERS rows with that PTY_PK deleted (NOT performed)
  -> Lookup_STG_TRS_DEACTIVED_MEMBERS + Filt_New_Only (not logged yet)
       -> STG_TRS_DEACTIVED_MEMBERS (PROCESSED_YN 'N', LOAD_DATE = run start)
A later process sends the unprocessed keys to the MDM.


Not performed: the IDQ DD_DELETE of STG_TRS_VALID_MEMBERS. Insert only, so deactivated members stay in the valid
list (gathered-kb-todos-and-improvements-002.md N5 / D12).
```

## Validations

```text
VALIDATION: none (no rule runs here).
```

## Bad data

```text
BAD DATA: STG_TRS_DEACTIVED_MEMBERS has primary key INDV_ID, which Snowflake does not enforce. An individual can be
  a valid member under two party keys (INDV_ID|DC_INDV and INDV_ID for MCI); IDQ writes the first and the database
  rejects the second. Reproduced: one row per INDV_ID, and ids already in the table are skipped.
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
| `STG_TRS_DEACTIVED_MEMBERS` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
