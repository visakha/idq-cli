# m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`

Workflow `wf_ECI_Stage_Load`, step 7 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md); business description [`docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md`](../../../docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md); Oracle port [`sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (workflow wf_ECI_Stage_Load).

Phones and e-mail addresses of the ECI parties (V_ECI_ETL_SRC_FAMILY_PHONE) into C_S_ECI_PTY_RLE_PHN and
C_S_ECI_PTY_RLE_EADDR (both insert only, never truncated):
  -> fil_deactivated_status: party not in STG_ECI_PTY_INACTIVE_STS
  -> rtr_Phone_Email
       Email_Group (PHONE_EMAIL_TYPE = 'EADDRESS') -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
            Valid_Records (no looked-up exception code) -> C_S_ECI_PTY_RLE_EADDR
            Bad_Records                                 -> EXC_STG_BAD_REC_MEMB
       Default (every other row, including a NULL type)  -> rule_Phone_Std (7-digit numbers get '000' prefixed)
            -> RTR_Valid_PhoneNumbers
            Good_Records      (no code, or 'Missing_AreaCode') -> C_S_ECI_PTY_RLE_PHN
            Bad_Phone_Records (any code)                       -> EXC_STG_BAD_REC_MEMB
```

## Validations

```text
VALIDATION: rule_Phone_Std = fn_snow_helper23_common (cleaning) + RDM.REF_PHN_AREA_CD (fn_snow_helper44_common)
  + fn_snow_helper24_common (code; ECI: area code '000' -> Missing_AreaCode, main / other numbers may not be
  toll-free); rule_email_validation_v01 = fn_snow_helper22_common.
```

## Bad data

```text
BAD DATA: a 'Missing_AreaCode' phone matches both phone groups, so it is loaded AND logged (IDQ router semantics).
  An e-mail whose 'Invalid_Email' code is not configured in EXC_LOOKUP_CODE_VALUE is treated as valid and loaded,
  because the router tests the looked-up code (docs/common_insights.md section 3). The phone exception
  SRC_SYS_ID_1 is linked to an unfed port (PTY_FK) in IDQ and is written NULL; its type is the literal 'Bad Value'.
  The phone is written cleaned and cut to 10 characters (port precision of the rule). Unique keys Snowflake does
  not enforce are applied: C_S_ECI_PTY_RLE_PHN / _EADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = '1' on both targets; PERIOD_START_DATE = source PERIOD_START_DATE; the e-mail
  PERIOD_REFERENCE_TIME port is not fed in IDQ (NULL).
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_ECI_PTY_RLE_PHN` |
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_ECI_PTY_RLE_EADDR` |

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
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
