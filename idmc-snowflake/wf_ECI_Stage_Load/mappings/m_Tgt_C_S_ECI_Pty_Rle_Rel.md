# m_Tgt_C_S_ECI_Pty_Rle_Rel &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel`

Workflow `wf_ECI_Stage_Load`, step 9 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql); IDQ / CDI spec [`idmc/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Rle_Rel.md`](../../../idmc/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Rle_Rel.md); business description [`docs/mappings/018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md`](../../../docs/mappings/018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md); Oracle port [`sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Rel (workflow wf_ECI_Stage_Load).

Family <-> child relationships into C_S_ECI_PTY_RLE_REL (insert only, never truncated). Every STG_ECI_D_FAMILY row
is read twice (custom SQL, 'To Child' and 'From Child'):
  * To Child  : family -> child, relationship code = FAMILY_CD
  * From Child: child -> family, relationship code = FAMILY_CD || '|' || child gender (STG_ECI_SN_CHILD.GENDER)
  -> Filter_Fam_Child_Valid: neither the child (LPAD(ID_CHILD,10,'0')) nor the family (LPAD(ID_FAMILY,10,'0')||'F')
     is in STG_ECI_PTY_INACTIVE_STS
  -> Lkp_Rel_Tp_Code_Value (LOOKUP_CODE_VALUE, code types REL_TP / INVERSE_REL) -> Route_Good_vs_Exceptions
       Valid_Relations     (code translates)         -> C_S_ECI_PTY_RLE_REL
       Relation_Exceptions (code does not translate) -> EXC_STG_BAD_REC_MEMB ('Invalid_Relationship')
```

## Validations

```text
VALIDATION: the relationship code must translate in LOOKUP_CODE_VALUE (REL_TP / INVERSE_REL, source ECI).
```

## Bad data

```text
BAD DATA: an untranslated relationship is not loaded, only logged. The exception row writes the EXCEPTION_CODE
  returned by the EXC_LOOKUP_CODE_VALUE lookup (NULL when 'Invalid_Relationship' is not configured). Its key
  SRC_SYS_ID_3 ends in '|' (the master code is NULL; IDQ concatenates NULL as ''). Unique keys Snowflake does not
  enforce are applied: C_S_ECI_PTY_RLE_REL (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = family DATE_CREATED. CREATE_DATE = DATE_MODIFIED (as IDQ links it,
  docs/common_insights.md 1.12).
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_ECI_PTY_RLE_REL` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
