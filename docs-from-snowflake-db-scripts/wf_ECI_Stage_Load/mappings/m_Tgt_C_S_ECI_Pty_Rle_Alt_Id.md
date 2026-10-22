# m_Tgt_C_S_ECI_Pty_Rle_Alt_Id &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`

Workflow `wf_ECI_Stage_Load`, step 6 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md); business description [`docs/mappings/016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md`](../../../docs/mappings/016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md); Oracle port [`sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (workflow wf_ECI_Stage_Load).

Alternate ids of the ECI parties into C_S_ECI_PTY_RLE_ALT_ID (insert only, never truncated):
  Read_STG_ECI_D_CHILD (custom SQL: child ECI id 018, child SSN 004, Medicaid number 002 via STG_ECI_SN_CASE,
                        family ECI id 019)
    -> Filter: party (first 11 characters of the role key, '|' trimmed) not in STG_ECI_PTY_INACTIVE_STS
    -> Rtr_ALT_ID_Type
         CHILD_SSN    (004) -> rule_USA_SSN_Validation_post_June2011 -> RTR_Valid_SSN
                                Valid   -> Union -> target
                                Invalid -> Exp_SSN_Exceptions -> EXC_STG_BAD_REC_MEMB
         ECI_IDs  (018/019) -> Union -> target
         MEDICAID_NBR (002) -> rule_MEDICAID_ID_Std -> RTR_Valid_Medicaid_ID
                                Valid   -> Union -> target
                                Invalid -> Exp_Invalid_MedicaidId -> EXC_STG_BAD_REC_MEMB
         Default            -> not linked (no other type is read)
The id written is the SOURCE value (the standardized SSN / Medicaid id is only used for validation).
```

## Validations

```text
VALIDATION: rule_USA_SSN_Validation_post_June2011 = fn_snow_helper26_common (status 'Invalid' -> Invalid_SSN);
  rule_MEDICAID_ID_Std = fn_snow_helper27_common (special characters removed, not 9 characters ->
  Invalid_Medicaid_Id).
```

## Bad data

```text
BAD DATA: an invalid SSN or Medicaid id is not loaded, only logged. The SSN exception row has no RUN_DATE linked
  (NULL, docs/common_insights.md 1.13) and writes the EXCEPTION_CODE returned by the EXC_LOOKUP_CODE_VALUE lookup
  (NULL when Invalid_SSN is not configured); the Medicaid exception row writes the computed code.
  Unique keys Snowflake does not enforce are applied: C_S_ECI_PTY_RLE_ALT_ID (PKEY_SRC_OBJECT, VERSION_SEQ) and
  EXC_STG_BAD_REC_MEMB (SRC_SYS, SRC_SYS_ID_1..3, EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE). Because the SSN row's
  RUN_DATE is NULL, its key repeats from run to run: in Oracle the unique constraint rejects the row of every later
  run, so an invalid SSN is logged only once, ever. That is reproduced here (key already in the table -> skipped).
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = source DATE_CREATED.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_ECI_PTY_RLE_ALT_ID` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper26_common` | rule_USA_SSN_Validation_post_June2011 (OBJECT) |
| `fn_snow_helper27_common` | rule_MEDICAID_ID_Std (OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
