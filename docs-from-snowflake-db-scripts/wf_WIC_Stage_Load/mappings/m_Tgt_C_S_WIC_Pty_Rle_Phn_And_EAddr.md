# m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`

Workflow `wf_WIC_Stage_Load`, step 4 of 5 in [`run_wf_WIC_Stage_Load.sql`](../../../idq-to-snowflake/wf_WIC_Stage_Load/run_wf_WIC_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql`](../../../idq-to-snowflake/wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_WIC_Stage_Load/mappings/m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md`](../../../docs-from-idq-exports/wf_WIC_Stage_Load/mappings/m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md); business description [`docs/mappings/033_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md`](../../../docs/mappings/033_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md); Oracle port [`sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`](../../../idq-to-oracle/wf_WIC_Stage_Load/sp_ors_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr (workflow wf_WIC_Stage_Load).

Each WIC row (V_WIC_ETL_SRC) gives one phone and possibly one e-mail:
  -> fil_deactivated_status: party not in STG_WIC_PTY_INACTIVE_STS, then two branches
  phone : rule_Phone_Std (usage 001 'Telephone', 'Primary') on EVERY active row -> RTR_Valid_PhoneNumbers
          Good_Records (no code, or 'Missing_AreaCode') -> C_S_WIC_PTY_RLE_PHN
          Bad_Phone_Records (any code)                 -> EXC_STG_BAD_REC_MEMB
  e-mail: Filt_null_email -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
          Valid_Records -> C_S_WIC_PTY_RLE_EADDR ; Bad_Records -> EXC_STG_BAD_REC_MEMB
```

## Validations

```text
VALIDATION: rule_Phone_Std = fn_snow_helper23/24_common with RDM.REF_PHN_AREA_CD ('Missing_AreaCode' only exists
  for ECI, so WIC never gets it); rule_email_validation_v01 = fn_snow_helper22_common (routed on the looked-up
  code).
```

## Bad data

```text
BAD DATA: there is no null-phone filter (docs/common_insights.md 1.14): a party without a phone is validated and
  logged as Invalid_Phone_Number. The e-mail key uses the e-mail as read (no trim), unlike ECI. Unique keys
  Snowflake does not enforce are applied: C_S_WIC_PTY_RLE_PHN / _EADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and
  EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = DATEKEY.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_WIC_PTY_RLE_PHN` |
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_WIC_PTY_RLE_EADDR` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper22_common` | rule_email_validation_v01 + local part + domain rules (OBJECT) |
| `fn_snow_helper23_common` | rule_Phone_Std, step 1: std_to_number cleaning (10 characters) |
| `fn_snow_helper24_common` | rule_Phone_Std, step 2: exception code (area code looked up by the caller) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper44_common` | RDM.REF_PHN_AREA_CD with the rule_Phone_Std filter: NPA_ID -> SERVICE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
