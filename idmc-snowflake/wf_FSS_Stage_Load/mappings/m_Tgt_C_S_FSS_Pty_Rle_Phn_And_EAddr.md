# m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`

Workflow `wf_FSS_Stage_Load`, step 5 of 6 in [`run_wf_FSS_Stage_Load.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql); IDQ / CDI spec [`idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md`](../../../idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md); business description [`docs/mappings/023_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md`](../../../docs/mappings/023_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md); Oracle port [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](../../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (workflow wf_FSS_Stage_Load).

Each FSS registration row (V_FSS_ETL_SRC, capture action not 'D') can give one e-mail and one phone:
  -> fil_deactivated_status: party not in STG_FSS_PTY_INACTIVE_STS, then two branches
  e-mail: Filt_null_email (ADDR_EMAIL not NULL) -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
          Valid_Records -> C_S_FSS_PTY_RLE_EADDR ; Bad_Records -> EXC_STG_BAD_REC_MEMB
  phone : Filt_null_phone (NBR_PHONE not NULL) -> rule_Phone_Std (usage 001 'Telephone', 'Primary') and
          rule_Phone_Extension_Std -> RTR_Valid_PhoneNumbers
          Good_Records (no phone code)  -> C_S_FSS_PTY_RLE_PHN (an invalid extension is blanked)
          Bad_Phone_Records             -> EXC_STG_BAD_REC_MEMB ('Rejected Record')
          Bad_Phone_Ext__Records        -> EXC_STG_BAD_REC_MEMB ('Bad Value')
```

## Validations

```text
VALIDATION: rule_email_validation_v01 = fn_snow_helper22_common (routed on the looked-up code);
  rule_Phone_Std = fn_snow_helper23/24_common with RDM.REF_PHN_AREA_CD; rule_Phone_Extension_Std =
  fn_snow_helper25_common.
```

## Bad data

```text
BAD DATA: a row with a good phone and a bad extension is loaded (extension blanked) AND logged as 'Bad Value'
  (docs/common_insights.md section 2). An e-mail whose code is not configured in EXC_LOOKUP_CODE_VALUE is loaded.
  Unique keys Snowflake does not enforce are applied: C_S_FSS_PTY_RLE_EADDR / _PHN (PKEY_SRC_OBJECT,
  VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = DT_LAST_UPDATE.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_FSS_PTY_RLE_EADDR` |
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_FSS_PTY_RLE_PHN` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper22_common` | rule_email_validation_v01 + local part + domain rules (OBJECT) |
| `fn_snow_helper23_common` | rule_Phone_Std, step 1: std_to_number cleaning (10 characters) |
| `fn_snow_helper24_common` | rule_Phone_Std, step 2: exception code (area code looked up by the caller) |
| `fn_snow_helper25_common` | rule_Phone_Extension_Std (OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper44_common` | RDM.REF_PHN_AREA_CD with the rule_Phone_Std filter: NPA_ID -> SERVICE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
