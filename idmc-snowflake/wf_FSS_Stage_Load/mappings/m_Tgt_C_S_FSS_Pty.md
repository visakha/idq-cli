# m_Tgt_C_S_FSS_Pty &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_FSS_Pty`

Workflow `wf_FSS_Stage_Load`, step 2 of 6 in [`run_wf_FSS_Stage_Load.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_FSS_Pty.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty.sql); IDQ / CDI spec [`idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty.md`](../../../idmc/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty.md); business description [`docs/mappings/020_m_Tgt_C_S_FSS_Pty.md`](../../../docs/mappings/020_m_Tgt_C_S_FSS_Pty.md); Oracle port [`sp_ors_main_m_Tgt_C_S_FSS_Pty`](../../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty (workflow wf_FSS_Stage_Load).

Loads the FSS clients (V_FSS_ETL_SRC, last active registration) into C_S_FSS_PTY and C_S_FSS_PTY_RLE (insert only,
never truncated) and logs demographic exceptions:
  -> Flt_Remove_Inactive: party not in STG_FSS_PTY_INACTIVE_STS
  -> name standardization (with the source suffix), gender, birth date, ethnicity (CD_HISPANIC), race
     indicators, language, rule_Suffix_Std
  -> Rtr_Exception: Valid_Party is TRUE (every active client loaded); each failed rule writes an
     EXC_STG_BAD_REC_MEMB row - gender, ethnicity and race only for SOURCE_TYPE = 'CLIENT', birth date, language
     and suffix for every row.
```

## Validations

```text
VALIDATION (common/01_snow_common_functions.sql): fn_snow_helper15_common name (suffix looked up with CODE_TYPE
  'SUFFIX'), fn_snow_helper17_common gender, fn_snow_helper16_common birth date, fn_snow_helper18_common
  ethnicity / language (V_LOOKUP_CODE_VALUE ETHNICITY / LANGUAGE_CD), fn_snow_helper19_common race indicators,
  fn_snow_helper20_common rule_Suffix_Std (V_LOOKUP_CODE_VALUE WITHOUT a code-type filter).
```

## Bad data

```text
BAD DATA: an exception never rejects the client: it is loaded AND logged. C_S_FSS_PTY.BIRTH_DT is the source DOB
  (IDQ links the source port, not the mapplet output, so a future birth date is still loaded); the language
  exception row writes the mapplet's birth date (NULL for a future one). Ethnicity, race and language exceptions
  write the looked-up code and are routed on it (unconfigured code = no row); gender is routed on the looked-up
  description. Unique keys Snowflake does not enforce are applied: C_S_FSS_PTY, C_S_FSS_PTY_RLE (PKEY_SRC_OBJECT,
  VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Party_Consolidation.v_VERS_SEQ_NUM); PERIOD_START_DATE =
  DT_LAST_UPDATE on both targets.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_PTY_BO_CLASS_CD_MEMBER` | VARCHAR | `'Indv'` | $PTY_BO_CLASS_CD_Member |
| `P_RLE_BO_CLASS_CD_MEMBER` | VARCHAR | `'Member'` | $RLE_BO_CLASS_CD_Member |

## Tables written (insert only)

| Table |
|---|
| `C_S_FSS_PTY` |
| `C_S_FSS_PTY_RLE` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper15_common` | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT) |
| `fn_snow_helper16_common` | mplt_BirthDate_Validation: exception code |
| `fn_snow_helper17_common` | mplt_Gender_Validation (OBJECT) |
| `fn_snow_helper18_common` | mplt_Race/Ethnicity/Language_Validation: exception code when the code is untranslated |
| `fn_snow_helper19_common` | mplt_Race_Ind_Validation (OBJECT) |
| `fn_snow_helper20_common` | rule_Suffix_Std: exception code |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper42_common` | V_LOOKUP_CODE_VALUE without a code-type filter (rule_Suffix_Std): SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper43_common` | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
