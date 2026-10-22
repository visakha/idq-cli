# m_Tgt_C_S_TTF_Pty_Validation &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation`

Workflow `wf_TTF_Stage_Load`, step 1 of 4 in [`run_wf_TTF_Stage_Load.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/run_wf_TTF_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty_Validation.md`](../../../docs-from-idq-exports/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty_Validation.md); business description [`docs/mappings/025_m_Tgt_C_S_TTF_Pty_Validation.md`](../../../docs/mappings/025_m_Tgt_C_S_TTF_Pty_Validation.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TTF_Pty_Validation`](../../../idq-to-oracle/wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty_Validation.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Validation (workflow wf_TTF_Stage_Load, first step).

Checks the TTF clients (V_TTF_ETL_SRC) and maintains the deactivation list used by every later TTF mapping. Party
key = LPAD(CLIENTS_ID, 10, '0'). Names are standardized with CopyOf_mplt_Name_Standardization_Indv_Member
(fn_snow_helper15_common; the TTF copy is identical apart from its name).
  * Rtr_Valid_Party.Invalid_Party_Name : first or last name blank, or 'DECLINED' / 'DO_NOT_DISCLOSE'
                                         -> EXC_STG_BAD_REC_MEMB (code Missing_/Invalid_First_/Last_Name)
  * Rtr_Valid_Party.Deactivation       : name blank or 'DECLINED' (not 'DO_NOT_DISCLOSE'), or
                                         CLIENT_EXISTS_FLAG = 'N'
                                         -> STG_TTF_PTY_INACTIVE_LOG ('Deactivation')
                                         -> STG_TTF_PTY_INACTIVE_STS (new row H / D / P, only when no status yet)
  * Rtr_Valid_Party.Reactivation       : has a status, names present and not 'DECLINED', CLIENT_EXISTS_FLAG = 'Y'
                                         -> STG_TTF_PTY_INACTIVE_LOG ('Reactivation')
  * Default group: not linked.


Not performed: the IDQ DD_DELETE of STG_TTF_PTY_INACTIVE_STS (Upd_Delete_Inactive). Insert only.
```

## Validations

```text
VALIDATION: blank test fn_snow_helper03_common on the standardized names; the placeholders 'DECLINED' and
  'DO_NOT_DISCLOSE' (any case) are invalid names. A 'DO_NOT_DISCLOSE' name is logged but does not deactivate.
```

## Bad data

```text
BAD DATA: the exception row writes the computed code, with description / type from EXC_LOOKUP_CODE_VALUE, and the
  source full name as ATTRIBUTE_VALUE. EXC_STG_BAD_REC_MEMB's unique key is applied (not enforced by Snowflake).
  The source read stores a SQL text that is only a WHERE fragment (test client ids) and is not in custom-query
  mode: it is not applied. Lookup_C_B_PTY_XREF: TRIM(ROWID_SYSTEM) = 'TTF' (the MDM column is blank padded).
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
| `STG_TTF_PTY_INACTIVE_LOG` |
| `STG_TTF_PTY_INACTIVE_STS` |

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
CALL sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
