# m_Tgt_C_S_TTF_Pty_Rle_Phn &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn`

Workflow `wf_TTF_Stage_Load`, step 4 of 4 in [`run_wf_TTF_Stage_Load.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/run_wf_TTF_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty_Rle_Phn.md`](../../../docs-from-idq-exports/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty_Rle_Phn.md); business description [`docs/mappings/028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md`](../../../docs/mappings/028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Phn`](../../../idq-to-oracle/wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty_Rle_Phn (workflow wf_TTF_Stage_Load).

One phone per active TTF client (V_TTF_ETL_SRC) into C_S_TTF_PTY_RLE_PHN (insert only, never truncated):
  -> fil_deactivated_status: party not in STG_TTF_PTY_INACTIVE_STS
  -> Filt_null_phone: PHONE not NULL
  -> rule_Phone_Std (usage 001 'Telephone', 'Primary') -> RTR_Valid_PhoneNumbers
       Good_Records (no code)      -> C_S_TTF_PTY_RLE_PHN
       Bad_Phone_Records (a code)  -> EXC_STG_BAD_REC_MEMB ('Rejected Record')
       Bad_Phone_Ext__Records      -> never: the extension port feeding rule_Phone_Extension_Std is not fed in IDQ
                                      (docs/common_insights.md 1.5), so the rule returns no code. Not generated.
```

## Validations

```text
VALIDATION: rule_Phone_Std = fn_snow_helper23_common + RDM.REF_PHN_AREA_CD (fn_snow_helper44_common) +
  fn_snow_helper24_common ('TTF', '001').
```

## Bad data

```text
BAD DATA: a bad phone is not loaded, only logged; the exception row writes the computed code and the source
  phone. SRC_SYS_ID_2 of the exception row is linked to a router port without input (ID_PHONE): NULL. The source
  read stores an invalid SQL fragment ("PHONE" in ()) that is not in custom-query mode: not applied. Unique keys
  Snowflake does not enforce are applied: C_S_TTF_PTY_RLE_PHN (PKEY_SRC_OBJECT, VERSION_SEQ) and
  EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = '1'; PERIOD_START_DATE = SUBMITDATE.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_TTF_PTY_RLE_PHN` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper23_common` | rule_Phone_Std, step 1: std_to_number cleaning (10 characters) |
| `fn_snow_helper24_common` | rule_Phone_Std, step 2: exception code (area code looked up by the caller) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper44_common` | RDM.REF_PHN_AREA_CD with the rule_Phone_Std filter: NPA_ID -> SERVICE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
