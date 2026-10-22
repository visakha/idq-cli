# m_Tgt_C_S_TRS_Pty_Rle_Alt_Id &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 11 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md); business description [`docs/mappings/004_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md`](../../../docs/mappings/004_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Alt_Id (workflow wf_TRS_Stage_Load_1_Ongoing).

Alternate ids of valid TIERS members into C_S_TRS_PTY_RLE_ALT_ID (insert only, never truncated):
  Read_STG_TRS_D_DC_INDV (custom SQL: MCI, DC_INDV and merged-individual keys of valid members, one row per key
    keeping the longest, latest SSN)
  -> lkp_Valid_SSN: the SSN is used only when STG_TRS_H_DC_INDV has it SSA-validated for the individual
  -> mplt_TRS_Pty_Rle_Alt_Id_Normalization (fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id + the steps below):
     Medicaid id and member id (both the member id), validated SSN; one row per non-empty id
       valid rows   -> srtr_Pkey -> exp_Rank / fltr_Rank (TIMELINE) -> target
       invalid rows -> EXC_STG_BAD_REC_MEMB (written INSIDE the IDQ mapplet; written here by the procedure)
```

## Validations

```text
VALIDATION: rule_MEDICAID_ID_Std (9 characters; the member id is fed as the Medicaid id, so a 10-character member id
  fails it), rule_Member_Id_Std (9 or 10 characters), rule_USA_SSN_Validation_post_June2011 (common functions 26-28).
```

## Bad data

```text
BAD DATA: an invalid SSN is blanked and then dropped, never logged (docs/common_insights.md 1.6). An invalid Medicaid
  or member id is not loaded and is logged with the computed code, the looked-up description, type 'Bad Value' and
  the ALT_ID_TP label as ATTRIBUTE_NAME. When LKP_ALT_ID_LBL does not find a type, the key has an empty type part,
  so the Medicaid and member rows of one person (same value) get the SAME key: C_S_TRS_PTY_RLE_ALT_ID is unique on
  (PKEY_SRC_OBJECT, VERSION_SEQ) and IDQ gets the second row rejected. Snowflake does not enforce that unique key:
  the first row per key is written and keys already in the table are skipped. Unfed ports written as NULL:
  ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND. The stored source filter INDV_ID = 504937068 is not
  part of the custom query and is not applied.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it):
  * exp_Rank ranks versions per key but VERSION_SEQ is hard-coded to 1 (the rank is commented out), so fltr_Rank
    (VERSION_SEQ = 1) keeps EVERY row (docs/common_insights.md 1.7). VERSION_SEQ = 1.
  * PERIOD_START_DATE / CREATE_DATE / SRC_LAST_UPD_DT = START_DT; PERIOD_END_DATE, PERIOD_REFERENCE_TIME,
    TIMELINE_ACTION are linked to unfed ports (NULL).
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_TRS_PTY_RLE_ALT_ID` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` | Helper of sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id: the rule calls and the Normalizer of |
| `fn_snow_helper03_common` | IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) (BOOLEAN) |
| `fn_snow_helper04_common` | IDQ TO_DECIMAL(value, scale): non-numeric 0, NULL NULL |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper45_common` | LOOKUP_CODE_VALUE by master code (PHN_USG_TP, ALT_ID_TP): CODE_TYPE, SRC_SYS, MSTR_REF_CODE -> MSTR_REF_LABEL |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
