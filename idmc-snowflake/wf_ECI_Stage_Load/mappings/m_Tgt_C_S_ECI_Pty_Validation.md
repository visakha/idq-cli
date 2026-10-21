# m_Tgt_C_S_ECI_Pty_Validation &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation`

Workflow `wf_ECI_Stage_Load`, step 1 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation.sql); IDQ / CDI spec [`idmc/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Validation.md`](../../../idmc/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Validation.md); business description [`docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md`](../../../docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md); Oracle port [`sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Validation (workflow wf_ECI_Stage_Load, first step).

Checks every ECI child and family party of the delta (STG_ECI_D_CHILD + STG_ECI_D_FAMILY) and maintains the
deactivation list that every later ECI mapping uses as a filter:
  * Rtr_Valid_Party.Invalid_Party_Name : standardized first or last name blank (and the family is not already
                                         inactive)                     -> EXC_STG_BAD_REC_MEMB
  * Rtr_Valid_Party.Deactivation       : name blank, or a duplicate case (V_ECI_ETL_LU_DUP_CASES), or the family is
                                         inactive (V_ECI_ETL_LU_FAMILY_VALIDATION)
                                         -> STG_ECI_PTY_INACTIVE_LOG ('Deactivation')
                                         -> STG_ECI_PTY_INACTIVE_STS (new row, only when the party has no status yet;
                                            H / D / P from the C_B_PTY_XREF hub state)
  * Rtr_Valid_Party.Reactivation       : party has a status, names present, not a duplicate, family active
                                         -> STG_ECI_PTY_INACTIVE_LOG ('Reactivation')
  * Default group                      : not linked, rows dropped.
A row goes to every group whose condition is true (IDQ router semantics), so Invalid_Party_Name rows are also
Deactivation rows.


Not performed: the IDQ DD_DELETE of STG_ECI_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
Snapshot: the lookups on STG_ECI_PTY_INACTIVE_STS read the table as it was before the run (IDQ static lookup
cache): all routing happens in one multi-table INSERT, which reads one snapshot.
Lookup Lookup_C_B_PTY_XREF: TRIM(ROWID_SYSTEM) = 'ECI' (the MDM column is blank-padded; Oracle compares a CHAR
column blank-padded, Snowflake does not).
v_FULL_NAME is declared string(10) in IDQ, so the full name passed to the name mapplet is cut at 10 characters
(BAD DATA); this mapping does not write the full-name outputs.
```

## Validations

```text
VALIDATION: mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common, with its prefix / suffix / junk-name
  lookups) cleans the names first; the blank test is the IDQ one (fn_snow_helper03_common: '' and white space are
  blank, NULL is blank). Missing_First_Name wins over Missing_Last_Name.
```

## Bad data

```text
BAD DATA: the exception row takes its description and type from EXC_LOOKUP_CODE_VALUE (NULL when the code is not
  configured) and writes the computed code. EXC_STG_BAD_REC_MEMB is unique on (SRC_SYS, SRC_SYS_ID_1..3,
  EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE) in Oracle; Snowflake does not enforce that, so a second row with the
  same key in this run is not written (IDQ rejects it and carries on).
```

## MDM timeline

```text
TIMELINE: this mapping has no MDM timeline logic.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `EXC_STG_BAD_REC_MEMB` |
| `STG_ECI_PTY_INACTIVE_LOG` |
| `STG_ECI_PTY_INACTIVE_STS` |

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
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
