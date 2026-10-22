# m_Tgt_C_S_WIC_Pty_Validation &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation`

Workflow `wf_WIC_Stage_Load`, step 1 of 5 in [`run_wf_WIC_Stage_Load.sql`](../../../idq-to-snowflake/wf_WIC_Stage_Load/run_wf_WIC_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`](../../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_WIC_Stage_Load/mappings/m_Tgt_C_S_WIC_Pty_Validation.md`](../../../docs-from-idq-exports/wf_WIC_Stage_Load/mappings/m_Tgt_C_S_WIC_Pty_Validation.md); business description [`docs/mappings/029_m_Tgt_C_S_WIC_Pty_Validation.md`](../../../docs/mappings/029_m_Tgt_C_S_WIC_Pty_Validation.md); Oracle port [`sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation`](../../../idq-to-oracle/wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty_Validation.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Validation (workflow wf_WIC_Stage_Load, first step).

Checks the WIC parties (V_WIC_ETL_SRC) and maintains the deactivation list used by every later WIC mapping:
  * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank      -> EXC_STG_BAD_REC_MEMB
  * Rtr_Valid_Party.Deactivation       : the same condition
                                         -> STG_WIC_PTY_INACTIVE_LOG ('Deactivation')
                                         -> STG_WIC_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
  * Rtr_Valid_Party.Reactivation       : has a status and both names present
                                         -> STG_WIC_PTY_INACTIVE_LOG ('Reactivation')
  * Default group: not linked.


Not performed: the IDQ DD_DELETE of STG_WIC_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
Snapshot: all routing happens in one multi-table INSERT, so the lookups see the pre-run status.
```

## Validations

```text
VALIDATION: mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common) then the IDQ blank test.
```

## Bad data

```text
BAD DATA: the exception row writes the computed code (Missing_First_Name / Missing_Last_Name) with the looked-up
  description / type. EXC_STG_BAD_REC_MEMB's unique key is applied (not enforced by Snowflake).
  Lookup_C_B_PTY_XREF: TRIM(ROWID_SYSTEM) = 'WIC' (blank-padded MDM column).
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
| `STG_WIC_PTY_INACTIVE_LOG` |
| `STG_WIC_PTY_INACTIVE_STS` |

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
CALL sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
