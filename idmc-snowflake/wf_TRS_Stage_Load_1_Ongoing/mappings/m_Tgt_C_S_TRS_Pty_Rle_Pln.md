# m_Tgt_C_S_TRS_Pty_Rle_Pln &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 12 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql); IDQ / CDI spec [`idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Pln.md`](../../../idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Pln.md); business description [`docs/mappings/005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md`](../../../docs/mappings/005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Pln (workflow wf_TRS_Stage_Load_1_Ongoing).

Managed-care plans of valid MCI members (STG_TRS_D_IN_MANAGED_CARE, plan present, begin before end or open) into
C_S_TRS_PTY_RLE_PLN (insert only, never truncated):
  -> lkp_Plan_Cd (V_LOOKUP_CODE_VALUE, code type PLAN_CD, source system 'MAX') -> rtr_Invalid_Plan_Cd
       VALID (plan translates) -> srtr_Pkey -> agg_Dedup_Rec (one row per INDV_ID|Member|plan) -> target
       Default                 -> exp_Rank + fltr_Rank: the FIRST invalid row per individual (source order
                                  INDV_ID, MC_PLAN, BEGIN_DT, END_DT) -> EXC_STG_BAD_REC_MEMB ('Invalid_Plan')
```

## Validations

```text
VALIDATION: the plan code must translate in V_LOOKUP_CODE_VALUE (PLAN_CD, looked up under source system 'MAX').
```

## Bad data

```text
BAD DATA: rows with begin >= end are dropped by the source query; only the first invalid plan per individual is
  logged (computed code 'Invalid_Plan', looked-up description / type). agg_Dedup_Rec returns the last row of each
  key in srtr_Pkey order (key, PERIOD_START_DATE, PERIOD_END_DATE, PLN_FK, PTY_RLE_FK; ascending, NULL high).
  Unfed ports written as NULL: UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_*. Unique keys Snowflake
  does not enforce are applied: C_S_TRS_PTY_RLE_PLN (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ hard-coded to 1 (exp_Safe_C_S_TRS_PTY_RLE_PLN.v_VERS_SEQ_NUM); PERIOD_START_DATE /
  PERIOD_END_DATE = BEGIN_DT / END_DT of the last (latest) segment of the key.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_TRS_PTY_RLE_PLN` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
