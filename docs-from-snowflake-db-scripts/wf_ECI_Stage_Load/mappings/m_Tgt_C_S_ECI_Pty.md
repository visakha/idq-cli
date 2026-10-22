# m_Tgt_C_S_ECI_Pty &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_ECI_Pty`

Workflow `wf_ECI_Stage_Load`, step 2 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_ECI_Pty.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty.md); business description [`docs/mappings/014_m_Tgt_C_S_ECI_Pty.md`](../../../docs/mappings/014_m_Tgt_C_S_ECI_Pty.md); Oracle port [`sp_ors_main_m_Tgt_C_S_ECI_Pty`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty (workflow wf_ECI_Stage_Load).

Loads the ECI child and family parties of the delta into C_S_ECI_PTY and C_S_ECI_PTY_RLE (insert only, never
truncated) and logs demographic exceptions:
  Read_STG_ECI_D_CHILD_AND_FAMILY (custom SQL)
    -> Flt_Remove_Inactive: IsNull(DEACTIVATION_STS) on STG_ECI_PTY_INACTIVE_STS (the stored condition is
       "--not IsNull(...)"; "--not" is an IDQ comment, so ACTIVE parties are kept)
    -> name standardization, gender, birth date, ethnicity, race indicators, language
    -> Rtr_Exception: Valid_Party is TRUE, so every active party is loaded; each failed rule additionally writes
       one EXC_STG_BAD_REC_MEMB row (ethnicity, race and language only for child rows).
The source read also stores a filter on five child ids; it is not part of the custom query and is ignored, as in
IDQ (custom query mode).


Target load order (IDQ): Write_Invalid_Party_Ethnicity before Write_Invalid_Party_Race; the INTO clauses keep that
order.
```

## Validations

```text
VALIDATION (mapplets written out in common/01_snow_common_functions.sql):
  mplt_Name_Standardization_Indv_Member  fn_snow_helper15_common (+ REF_JUNK_NAME_LIST lookup)
  mplt_Gender_Validation                 fn_snow_helper17_common   -> Invalid_Gender (routed on the looked-up
                                                                      description: unconfigured code = no row)
  mplt_BirthDate_Validation              fn_snow_helper16_common   -> Invalid_Birth_Date (birth date then NULL)
  mplt_Ethnicity_Validation              fn_snow_helper18_common + V_LOOKUP_CODE_VALUE ETHNICITY
  mplt_Race_Ind_Validation               fn_snow_helper19_common   -> Invalid_Race
  mplt_Language_Validation               fn_snow_helper18_common + V_LOOKUP_CODE_VALUE LANGUAGE_CD
  Ethnicity, race and language exceptions write the code as RETURNED by the EXC_LOOKUP_CODE_VALUE lookup and are
  routed on it (or on its description), so an exception that is not configured writes no row.
```

## Bad data

```text
BAD DATA: an exception never rejects the party (Valid_Party = TRUE): the party is loaded AND logged. A future
  birth date is loaded as NULL. Exception rows carry MAPPING_NAME 'm_Tgt_C_S_ECI_Pty_OnGoing' (literal in the
  IDQ expressions). Unique keys that Snowflake does not enforce are applied here: C_S_ECI_PTY and C_S_ECI_PTY_RLE
  (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB (SRC_SYS, SRC_SYS_ID_1..3, EXCEPTION_TYPE,
  EXCEPTION_CODE, RUN_DATE): a row whose key is already in the table, or already written in this run, is not
  written (IDQ rejects it and carries on).
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported here as IDQ does it):
  * VERSION_SEQ is hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM = 1) on both targets.
  * exp_Party_Consolidation also computes DUP_RANK and an MD5 of the demographics for the timeline; neither is
    written by IDQ, so they are not computed here.
  * PERIOD_START_DATE: party = source DATE_MODIFIED (DATE_MODIFIED, else DATE_CREATED); role = DATE_CREATED.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_PTY_BO_CLASS_CD_MEMBER` | VARCHAR | `'Indv'` | $PTY_BO_CLASS_CD_Member |
| `P_RLE_BO_CLASS_CD_MEMBER` | VARCHAR | `'Member'` | $RLE_BO_CLASS_CD_Member |

## Tables written (insert only)

| Table |
|---|
| `C_S_ECI_PTY` |
| `C_S_ECI_PTY_RLE` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper15_common` | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT) |
| `fn_snow_helper16_common` | mplt_BirthDate_Validation: exception code |
| `fn_snow_helper17_common` | mplt_Gender_Validation (OBJECT) |
| `fn_snow_helper18_common` | mplt_Race/Ethnicity/Language_Validation: exception code when the code is untranslated |
| `fn_snow_helper19_common` | mplt_Race_Ind_Validation (OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper43_common` | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
