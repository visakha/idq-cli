# m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 7 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md); business description [`docs/mappings/006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md`](../../../docs/mappings/006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr (workflow
wf_TRS_Stage_Load_1_Ongoing).

Phones and e-mail of the TIERS case delta (STG_TRS_D_DC_CASES x STG_TRS_DC_CASE_INDV, valid members only) into
C_S_TRS_PTY_RLE_PHN and C_S_TRS_PTY_RLE_EADDR (insert only, never truncated):
  -> fltr_Hold (TRUE)
  phones: mplt_Phone_Normalization (fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr + the steps below):
          main PH_NUM (001), work WORK_PH_NUM || ' ' || WORK_PH_NUM_EXT (002), other OTHER_PH_NUM (003); each
          through rule_Phone_Std, Filter_Null_Phone_Nums, LOOKUP_CODE_VALUE PHN_USG_TP for the key
          -> rtr_Valid_Phone_Records
               Valid_Records (no code) -> mplt_Phone_Consolidation -> srtr_Pty_Rle_Phone + agg_Pty_Rle_Phone
                                          -> C_S_TRS_PTY_RLE_PHN
               Default (a code)        -> EXC_STG_BAD_REC_MEMB
  e-mail: fltr_Null_Emails -> rule_email_validation_v01 -> rtr_Valid_EAddr_Records
               Valid_Records -> mplt_EAddr_Consolidation -> srtr_Pty_Rle_Eaddr + agg_Pty_Rle_Eaddr
                                -> C_S_TRS_PTY_RLE_EADDR
               Default       -> EXC_STG_BAD_REC_MEMB
```

## Validations

```text
VALIDATION: rule_Phone_Std (fn_snow_helper23/24_common with RDM.REF_PHN_AREA_CD). Inside
  mplt_Member_Pty_Rle_Phn_Normalization the three rule instances get ONLY the phone: their SRC_SYS and USG_TP
  inputs are not linked, so the TRS / main-number toll-free check of the rule never runs here
  (docs/common_insights.md 9). rule_email_validation_v01 (fn_snow_helper22_common), routed on the looked-up code.
```

## Bad data

```text
BAD DATA: the work phone is fed as "number extension"; the rule removes the space and its string(10) port keeps
  the first ten characters, so the extension is dropped and the number itself is validated and written (port
  precision, docs/common_insights.md 9). Failed phones / e-mails are not loaded, only logged ('Bad Value' for
  phones). Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND, USG_TP
  (e-mail). The stored source filter rownum < 100000 is not part of the custom query and is not applied. Unique
  keys Snowflake does not enforce are applied: C_S_TRS_PTY_RLE_PHN / _EADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and
  EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it):
  * mplt_Member_Pty_Rle_Phn_Consolidation / mplt_Member_Pty_Rle_EAddr_Consolidation (set level, inlined): drop
    NULL numbers / addresses, distinct sort on (FILE_DATE - not fed -, PKEY_SRC_OBJECT, PERIOD_START_DATE),
    running VERSION_SEQ per key; the aggregator keeps the LAST row of the key, so VERSION_SEQ = number of distinct
    versions of that key.
  * PERIOD_END_DATE = MAX of a port that is not fed (NULL); PERIOD_REFERENCE_TIME and TIMELINE_ACTION are linked
    to unfed ports (NULL).
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_TRS_PTY_RLE_PHN` |
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_TRS_PTY_RLE_EADDR` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` | Helper of sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr: the Normalizer of mplt_Member_Pty_Rle_Phn_Normalization |
| `fn_snow_helper22_common` | rule_email_validation_v01 + local part + domain rules (OBJECT) |
| `fn_snow_helper23_common` | rule_Phone_Std, step 1: std_to_number cleaning (10 characters) |
| `fn_snow_helper24_common` | rule_Phone_Std, step 2: exception code (area code looked up by the caller) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper44_common` | RDM.REF_PHN_AREA_CD with the rule_Phone_Std filter: NPA_ID -> SERVICE |
| `fn_snow_helper45_common` | LOOKUP_CODE_VALUE by master code (PHN_USG_TP, ALT_ID_TP): CODE_TYPE, SRC_SYS, MSTR_REF_CODE -> MSTR_REF_LABEL |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
