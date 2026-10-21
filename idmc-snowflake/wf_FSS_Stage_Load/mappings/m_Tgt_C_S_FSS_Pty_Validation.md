# m_Tgt_C_S_FSS_Pty_Validation &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation`

Workflow `wf_FSS_Stage_Load`, step 1 of 6 in [`run_wf_FSS_Stage_Load.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql); IDQ / CDI spec [`idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Validation.md`](../../../idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Validation.md); business description [`docs/mappings/019_m_Tgt_C_S_FSS_Pty_Validation.md`](../../../docs/mappings/019_m_Tgt_C_S_FSS_Pty_Validation.md); Oracle port [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation`](../../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Validation.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Validation (workflow wf_FSS_Stage_Load, first step).

Checks the FSS clients (V_FSS_ETL_SRC, rows that are the last active registration of a client or that mark all
registrations inactive) and maintains the deactivation list used by every later FSS mapping:
  * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank      -> EXC_STG_BAD_REC_MEMB
  * Rtr_Valid_Party.Deactivation       : name blank, client deleted (CLIENT_DTL__CAPXACTION = 'D') or all
                                         registrations inactive (LAST_INACTV_CLIENT_YN = 'Y')
                                         -> STG_FSS_PTY_INACTIVE_LOG ('Deactivation')
                                         -> STG_FSS_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
  * Rtr_Valid_Party.Reactivation       : has a status, names present, not deleted, not all inactive
                                         -> STG_FSS_PTY_INACTIVE_STS row inserted with DEACTIVATION_STS =
                                            'Reactivation' (IDQ links Exp_Log_Reactv to the STATUS table, not the
                                            log; ported as observed, docs/common_insights.md 1.1). Because later
                                            mappings skip any key with a non-null status, a reactivated FSS client
                                            stays excluded - confirm with the business.
  * Default group: not linked.


Not performed: the IDQ DD_DELETE of STG_FSS_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
Snapshot: one multi-table INSERT, so the status lookup reads the table as it was before the run.
```

## Validations

```text
VALIDATION: mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common) then the IDQ blank test
  (fn_snow_helper03_common). A NULL capture action or inactive flag: "x <> 'D'" is not true for NULL in IDQ or
  Snowflake, so such rows are not reactivated (docs/common_insights.md section 6).
```

## Bad data

```text
BAD DATA: the exception row writes the computed code with the looked-up description / type, and the source full
  name as ATTRIBUTE_VALUE. EXC_STG_BAD_REC_MEMB's unique key is applied (Snowflake does not enforce it).
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
| `EXC_STG_BAD_REC_MEMB` |
| `STG_FSS_PTY_INACTIVE_LOG` |
| `STG_FSS_PTY_INACTIVE_STS` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper02_common` | new deactivation status from the hub state: H history / D deactivated / P pending |
| `fn_snow_helper03_common` | IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) (BOOLEAN) |
| `fn_snow_helper15_common` | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper43_common` | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
