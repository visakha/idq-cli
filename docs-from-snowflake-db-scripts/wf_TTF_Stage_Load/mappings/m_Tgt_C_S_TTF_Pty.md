# m_Tgt_C_S_TTF_Pty &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TTF_Pty`

Workflow `wf_TTF_Stage_Load`, step 2 of 4 in [`run_wf_TTF_Stage_Load.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/run_wf_TTF_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TTF_Pty.sql`](../../../idq-to-snowflake/wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty.md`](../../../docs-from-idq-exports/wf_TTF_Stage_Load/mappings/m_Tgt_C_S_TTF_Pty.md); business description [`docs/mappings/026_m_Tgt_C_S_TTF_Pty.md`](../../../docs/mappings/026_m_Tgt_C_S_TTF_Pty.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TTF_Pty`](../../../idq-to-oracle/wf_TTF_Stage_Load/sp_ors_main_m_Tgt_C_S_TTF_Pty.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TTF_Pty (workflow wf_TTF_Stage_Load).

Loads the TTF clients (V_TTF_ETL_SRC) into C_S_TTF_PTY and C_S_TTF_PTY_RLE (insert only, never truncated) and logs
demographic exceptions:
  -> Flt_Remove_Inactive: party (PTY_SRC_KEY) not in STG_TTF_PTY_INACTIVE_STS
  -> Expression: gender from SEXID (33 -> F, 34 -> M, else U); ethnicity = '55' when RACEETHNICITYID = '55'
  -> name standardization (TTF CopyOf_ mapplet), gender, birth date, ethnicity, race by code (mplt_Race_Validation
     on RACEETHNICITYID)
  -> Rtr_Exception: Valid_Party is TRUE (every active client loaded); birth date, gender, ethnicity and race
     failures each write an EXC_STG_BAD_REC_MEMB row for every row (no source-table condition in TTF).
```

## Validations

```text
VALIDATION: fn_snow_helper15_common (name), fn_snow_helper17_common (gender, routed on the looked-up description),
  fn_snow_helper16_common (birth date), fn_snow_helper18_common with V_LOOKUP_CODE_VALUE ETHNICITY / RACE
  (routed on the looked-up code). The Invalid_Language / Invalid_Suffix router groups test ports that are not fed
  in IDQ and have no target, so they never write (docs/common_insights.md 1.4): not generated.
```

## Bad data

```text
BAD DATA: an exception never rejects the client (loaded AND logged); a future birth date is loaded as NULL.
  PRFRD_LANG_CD and SFX_NM are linked to unfed ports in IDQ (NULL). Unique keys Snowflake does not enforce are
  applied: C_S_TTF_PTY, C_S_TTF_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ hard-coded to 1; party PERIOD_START_DATE = run start ($sys.MappingRunStartTime, so it
  changes on every run: docs/common_insights.md 1.11), role PERIOD_START_DATE = SUBMITDATE.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_PTY_BO_CLASS_CD_MEMBER` | VARCHAR | `'Indv'` | $PTY_BO_CLASS_CD_Member |
| `P_RLE_BO_CLASS_CD_MEMBER` | VARCHAR | `'Member'` | $RLE_BO_CLASS_CD_Member |

## Tables written (insert only)

| Table |
|---|
| `C_S_TTF_PTY` |
| `C_S_TTF_PTY_RLE` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper15_common` | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT) |
| `fn_snow_helper16_common` | mplt_BirthDate_Validation: exception code |
| `fn_snow_helper17_common` | mplt_Gender_Validation (OBJECT) |
| `fn_snow_helper18_common` | mplt_Race/Ethnicity/Language_Validation: exception code when the code is untranslated |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper43_common` | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TTF_Pty();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
