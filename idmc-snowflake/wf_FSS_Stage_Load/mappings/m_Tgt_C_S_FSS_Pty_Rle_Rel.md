# m_Tgt_C_S_FSS_Pty_Rle_Rel &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel`

Workflow `wf_FSS_Stage_Load`, step 6 of 6 in [`run_wf_FSS_Stage_Load.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql); IDQ / CDI spec [`idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Rle_Rel.md`](../../../idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Rle_Rel.md); business description [`docs/mappings/024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md`](../../../docs/mappings/024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md); Oracle port [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel`](../../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Rel (workflow wf_FSS_Stage_Load).

Relationships between FSS clients (V_FSS_ETL_SRC_RELATIONS, one row per direction) into C_S_FSS_PTY_RLE_REL
(insert only, never truncated):
  -> Filter_Fam_Child_Valid: neither PTY_SRC_KEY nor RELN_PTY_SRC_KEY is in STG_FSS_PTY_INACTIVE_STS
  -> Exp_Map_Code_Val_and_Gender: relation code (CAREGIVER when missing) || '|' || gender of the related party
     ('To Child': RELN_CD_GENDER with code type REL_TP; otherwise CD_GENDER with code type INVERSE_REL)
  -> Lkp_Rel_Tp_Code_Value (LOOKUP_CODE_VALUE) -> Route_Good_vs_Exceptions
       Valid_Relations     -> C_S_FSS_PTY_RLE_REL
       Relation_Exceptions -> EXC_STG_BAD_REC_MEMB ('Invalid_Relationship', attribute 'Relationship|Sex', gender)
```

## Validations

```text
VALIDATION: the relation code must translate in LOOKUP_CODE_VALUE for the direction's code type.
```

## Bad data

```text
BAD DATA: an untranslated relationship is not loaded, only logged, with the looked-up EXCEPTION_CODE (NULL when
  'Invalid_Relationship' is not configured). Unique keys Snowflake does not enforce are applied:
  C_S_FSS_PTY_RLE_REL (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = RELN_DT_CREATED.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_FSS_PTY_RLE_REL` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
