# m_Tgt_C_S_CRE_CARE_Clients &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients`

Workflow `wf_CRE_Stage_Load_Ongoing`, step 1 of 1 in [`run_wf_CRE_Stage_Load_Ongoing.sql`](../../../idq-to-snowflake/wf_CRE_Stage_Load_Ongoing/run_wf_CRE_Stage_Load_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql`](../../../idq-to-snowflake/wf_CRE_Stage_Load_Ongoing/sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_CRE_Stage_Load_Ongoing/mappings/m_Tgt_C_S_CRE_CARE_Clients.md`](../../../docs-from-idq-exports/wf_CRE_Stage_Load_Ongoing/mappings/m_Tgt_C_S_CRE_CARE_Clients.md); business description [`docs/mappings/034_m_Tgt_C_S_CRE_CARE_Clients.md`](../../../docs/mappings/034_m_Tgt_C_S_CRE_CARE_Clients.md); Oracle port [`sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients`](../../../idq-to-oracle/wf_CRE_Stage_Load_Ongoing/sp_ors_main_m_Tgt_C_S_CRE_CARE_Clients.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_CRE_CARE_Clients (workflow wf_CRE_Stage_Load_Ongoing, its
only mapping).

Loads the CARE clients into CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN and
C_S_CRE_PTY_RLE_ALT_ID (insert only, never truncated) and logs exceptions:
  -> custom SQL: new and changed clients ('I'), deleted ('D') and moved ('B') cases from the snapshot
     STG_CRE_SN_CARE_CLIENTS through STG_CRE_D_CARE_CASE_MAINT, the targets of the moves ('A')
  -> RTR_MERGES: rows that are not regular or deleted (DELETES group) look the source and target CARE ids up in
     C_B_PTY_XREF and their original records in C_B_PTY_HMRG; no merge history at all -> CRE_SRC_MRG
  -> name standardization; a member needs a standardized first AND last name, otherwise the missing name is logged
  -> one row per CARE id (REC_TYPE descending: I, D, B, A) -> party, role, address (US: address validation; abroad:
     state 99, country ZZ), phone, and the three alternate ids (CARE ID, Medicaid ID, SSN)
```

## Validations

```text
VALIDATION: fn_snow_helper15_common (name, with the SUFFIX and junk-name lookups), fn_snow_helper17_common
  (gender), fn_snow_helper18_common with V_LOOKUP_CODE_VALUE ETHNICITY / RACE, fn_snow_helper23/24_common (phone,
  only the number linked: no toll-free check for CRE), fn_snow_helper27_common (Medicaid id),
  fn_snow_helper26_common (SSN), fn_snow_helper37_common (CARE id), fn_snow_helper34_common (address) and
  RTR_VALID_ADDRESS: (TO_INTEGER(mailability score) >= 3 OR match code not starting I / N) AND a state FIPS; abroad
  the city and street must be present. No birth-date rule. The name, phone and SSN routes and the address, gender,
  ethnicity and race exception rows use the code AS LOOKED UP in EXC_LOOKUP_CODE_VALUE (fn_snow_helper40_common):
  unconfigured means no name row, a loaded phone or SSN, an address row with a NULL code, no gender / ethnicity /
  race row. The suffix and Medicaid rows write the computed code.
```

## Bad data

```text
BAD DATA: invalid members are logged and dropped; a bad address, phone or alternate id is logged instead of loaded
  (the member itself is loaded); SSN 'U' / 'N' blanked and dropped; ids lose special characters and are cut to 10
  characters; phones are cut to 10 digits; SRC_ROWID is cut to 30 characters (IDQ truncates to the target
  precision); with the pass-through validator (no score, no match code) the RTR_VALID_ADDRESS condition is NULL, so
  every US address is an exception. Unique keys Snowflake does not enforce are applied: the C_S_* targets
  (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB (the name rows of a CARE id read twice, and the Medicaid
  and SSN rows that the source and the target of an unmerged move both log under the target id).
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = VERSION_SEQ_NUM (the rank per CARE id; 1 for every written row). 'B' and 'D' rows are
  end-dated: PERIOD_START_DATE = CARE_LASTUP_DT - 1 day, PERIOD_END_DATE = CARE_LASTUP_DT, TIMELINE_ACTION = 2,
  PERIOD_REFERENCE_TIME = PERIOD_START_DATE, LAST_UPDATE_DATE = run start - 1 hour (the role keeps the run start).
  The role and the alternate ids do not link TIMELINE_ACTION / PERIOD_REFERENCE_TIME (written NULL).
  IDQ quirks kept: CRE_SRC_MRG also gets moves whose CARE ids have no cross-reference (NULL records), and the move
  target row again when it carries a MAINT_FLAG; the CARE ID alternate id of an unmerged move is the target id; the
  state and alternate-id type lookups have no code-type filter (fn_snow_helper42_common / LOOKUP_CODE_VALUE by
  source value), so an untranslated type leaves ALT_ID_TP and the exception's SRC_SYS NULL.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_PHYSICAL_ADDR_TYPE_CD` | VARCHAR | `'002'` | $PHYSICAL_ADDR_TYPE_CD |
| `P_RLE_BO_CLASS_CD_MEMBER` | VARCHAR | `'Member'` | $RLE_BO_CLASS_CD_Member |
| `P_DEFAULT_TX_STATE_CD` | VARCHAR | `'48'` | $Default_TX_State_CD |
| `P_COUNTY_CD_NONTX` | VARCHAR | `'996'` | $County_CD_NonTX |
| `P_COUNTYCD_DEFAULTALL` | VARCHAR | `'998'` | $CountyCD_DefaultAll |
| `P_DEFAULT_NONUS_STATE_CD` | VARCHAR | `'99'` | $Default_NonUS_State_CD |

## Tables written (insert only)

| Table |
|---|
| `CRE_SRC_MRG` |
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_CRE_PTY` |
| `C_S_CRE_PTY_RLE` |
| `C_S_CRE_PTY_RLE_ADDR` |
| `C_S_CRE_PTY_RLE_PHN` |
| `C_S_CRE_PTY_RLE_ALT_ID` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper03_common` | IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) (BOOLEAN) |
| `fn_snow_helper15_common` | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT) |
| `fn_snow_helper17_common` | mplt_Gender_Validation (OBJECT) |
| `fn_snow_helper18_common` | mplt_Race/Ethnicity/Language_Validation: exception code when the code is untranslated |
| `fn_snow_helper23_common` | rule_Phone_Std, step 1: std_to_number cleaning (10 characters) |
| `fn_snow_helper24_common` | rule_Phone_Std, step 2: exception code (area code looked up by the caller) |
| `fn_snow_helper26_common` | rule_USA_SSN_Validation_post_June2011 (OBJECT) |
| `fn_snow_helper27_common` | rule_MEDICAID_ID_Std (OBJECT) |
| `fn_snow_helper34_common` | mplt_Global_Addr_Validation (pass-through validator, OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper37_common` | rule_CARE_ID_Std (CRE) (OBJECT) |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper42_common` | V_LOOKUP_CODE_VALUE without a code-type filter (rule_Suffix_Std): SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper43_common` | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |
| `fn_snow_helper44_common` | RDM.REF_PHN_AREA_CD with the rule_Phone_Std filter: NPA_ID -> SERVICE |
| `fn_snow_helper46_common` | ref_MatchCode_Desc (mplt_Global_Addr_Validation): MATCH_CODE -> DESCRIPTION |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
