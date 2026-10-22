# m_Tgt_C_S_TRS_Pty_Rle_TOA &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 3 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_TOA.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_TOA.md); business description [`docs/mappings/008_m_Tgt_C_S_TRS_Pty_Rle_TOA.md`](../../../docs/mappings/008_m_Tgt_C_S_TRS_Pty_Rle_TOA.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_TOA (workflow wf_TRS_Stage_Load_1_Ongoing).

Type of assistance of valid TIERS members (STG_TRS_D_CV_MCI_EDG_INDV_TOA, latest create per individual / EDG /
program / MCI sequence) into C_S_TRS_PTY_RLE_TOA (insert only, never truncated):
  -> lkp_LOOKUP_CODE_VALUE (code type TOA, source 'TRS') -> rtr_Valid_Records
       Bad_Value (TOA code does not translate)            -> EXC_STG_BAD_REC_MEMB ('Invalid_TOA')
       Period_Begin_Date_GT_Period_End_Date (BEGIN > END) -> EXC_STG_BAD_REC_MEMB
                                                             ('Period_Start_Date_>_Period_End_Date')
       Default (neither)                                  -> C_S_TRS_PTY_RLE_TOA
  Key = INDV_ID|Member|<TOA master code>|TIERS|<EDG_NUM>|<PROGRAM_CD>|<MCI_CREATE_SEQ>.
```

## Validations

```text
VALIDATION: the TOA code must translate in LOOKUP_CODE_VALUE (TOA, TRS); the eligibility begin date may not be
  after the end date.
```

## Bad data

```text
BAD DATA: a row with an untranslated code AND begin > end writes BOTH exception rows (router semantics). The
  Bad_Value row writes the looked-up EXCEPTION_CODE (NULL when 'Invalid_TOA' is not configured); the date row
  writes the computed code. Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR,
  HUB_STATE_IND, and the name / address / phone columns of the Bad_Value exception row. Unique keys Snowflake does
  not enforce are applied: C_S_TRS_PTY_RLE_TOA (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ is the source ROW_NUMBER() kept only where it equals 1, i.e. always 1; PERIOD_START_DATE /
  EFF_STRT_DT = BEGIN_DT, PERIOD_END_DATE / EFF_END_DT = END_DT; PERIOD_REFERENCE_TIME is linked to an unfed port.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_TRS_PTY_RLE_TOA` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
