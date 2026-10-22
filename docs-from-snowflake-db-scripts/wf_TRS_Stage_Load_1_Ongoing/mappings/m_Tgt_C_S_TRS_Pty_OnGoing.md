# m_Tgt_C_S_TRS_Pty_OnGoing &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 1 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_OnGoing.md); business description [`docs/mappings/001_m_Tgt_C_S_TRS_Pty_OnGoing.md`](../../../docs/mappings/001_m_Tgt_C_S_TRS_Pty_OnGoing.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_OnGoing (workflow wf_TRS_Stage_Load_1_Ongoing,
first step).

TIERS individuals (STG_TRS_D_DC_INDV and STG_TRS_D_CV_DC_MCI_INDV) that are valid today (custom SQL: new valid
individuals plus the existing valid members, minus today's inactivations and earlier deactivations):
  -> exp_interface: party key = INDV_ID || '|DC_INDV' for DC_INDV rows, INDV_ID for MCI rows
  -> name standardization (with prefix and suffix), gender, birth date, race (code), ethnicity (code); death date
     after the run start -> 'Invalid_Death_Date' (looked up in EXC_LOOKUP_CODE_VALUE)
  -> rtr_Invalid_Party (a row goes to every matching group):
       Invalid_Party_Name  (standardized first or last name blank) -> EXC_STG_BAD_REC_MEMB
       Invalid_Gender_Code                                         -> EXC_STG_BAD_REC_MEMB
       Invalid_Death_Date  (configured exception found)            -> EXC_STG_BAD_REC_MEMB
       Invalid_BirthDate                                           -> EXC_STG_BAD_REC_MEMB
       Valid_Party (first OR last name present)
         -> srtr_Dedup_Rec (distinct) -> fltr_Dups (TIMELINE)
            -> Sorter1 + Aggregator1 (one row per party key)      -> C_S_TRS_PTY
            -> Sorter  + Aggregator  (one row per role key)       -> C_S_TRS_PTY_RLE
            -> lkp_Stg_TRS_Valid_Members + fltr_New_Valid_Members (key not yet valid) -> STG_TRS_VALID_MEMBERS
            -> Fil_Race_Exceptions / Fil_Ethnicity_Exceptions (configured exception) -> EXC_STG_BAD_REC_MEMB

An IDQ aggregator without aggregate functions returns the LAST row of each group in arrival order. The rows arrive
in srtr_Dedup_Rec order (party key, update date, INDV_ID, SRC_TBL, gender, suffix, first, prefix, last, middle,
birth date, full name; ascending, NULL high); ROW_NUMBER() over the reverse of that order picks the same row.
```

## Validations

```text
VALIDATION: fn_snow_helper15_common name (V_LOOKUP_CODE_VALUE PREFIX / SUFFIX for 'TRS'), fn_snow_helper17_common
  gender, fn_snow_helper16_common birth date, fn_snow_helper18_common race / ethnicity (V_LOOKUP_CODE_VALUE RACE /
  ETHNICITY), death date > run start. The gender, death, race and ethnicity groups fire only when the exception is
  configured in EXC_LOOKUP_CODE_VALUE (docs/common_insights.md section 3).
```

## Bad data

```text
BAD DATA: a party with only one of its names is loaded AND logged (Valid_Party is first OR last name). Gender and
  death-date problems never reject a party. The race / ethnicity exception rows write the MASTER code as
  ATTRIBUTE_VALUE (fltr_Dups.Race_Cd is linked from MDM_Race_Cd), which is NULL exactly when the exception fires
  (docs/common_insights.md 1.8); these two targets are fed by a dynamic port group (FieldMapPort), resolved field by
  field. C_S_TRS_PTY.HUB_STATE_IND, UPDATED_BY, CREATE_DATE, CREATOR, FLAG_SRC and ROWID_OBJECT / DELETED_* are
  linked to unfed ports (NULL); the same holds for the role table. The stored source filter INDV_ID = 504937068 is
  not part of the custom query and is not applied. Unique keys Snowflake does not enforce are applied:
  C_S_TRS_PTY / C_S_TRS_PTY_RLE (PKEY_SRC_OBJECT, VERSION_SEQ), STG_TRS_VALID_MEMBERS (PTY_PK) and
  EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it):
  * exp_Party_Consolidation: VERSION_SEQ_NUM is hard-coded to 1 (the MD5 / version comparison is commented out in
    IDQ); DUP_RANK is computed by IDQ but not written - not computed here.
  * fltr_Dups keeps VERSION_SEQ_NUM = 1, i.e. every row (a no-op).
  * PERIOD_END_DATE = MAX(PERIOD_END_DATE) of a port that is not fed (NULL); PERIOD_REFERENCE_TIME and
    TIMELINE_ACTION are linked to unfed ports (NULL); PERIOD_START_DATE = CREATE_DT.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_PTY_BO_CLASS_CD_MEMBER` | VARCHAR | `'Indv'` | $PTY_BO_CLASS_CD_Member |
| `P_RLE_BO_CLASS_CD_MEMBER` | VARCHAR | `'Member'` | $RLE_BO_CLASS_CD_Member |
| `P_DC_INDV_TBL_SRC` | VARCHAR | `'DC_INDV'` | $DC_INDV_TBL_SRC |
| `P_MCI_TBL_SRC` | VARCHAR | `'MCI'` | $MCI_TBL_SRC |

## Tables written (insert only)

| Table |
|---|
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_TRS_PTY` |
| `C_S_TRS_PTY_RLE` |
| `STG_TRS_VALID_MEMBERS` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper03_common` | IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) (BOOLEAN) |
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
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
