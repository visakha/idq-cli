# m_Tgt_C_S_TRS_Stg_TOA &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA`

Workflow `wf_TRS_Stage_Load_TOA`, step 1 of 1 in [`run_wf_TRS_Stage_Load_TOA.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_TOA/run_wf_TRS_Stage_Load_TOA.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_TOA/sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_TOA/mappings/m_Tgt_C_S_TRS_Stg_TOA.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_TOA/mappings/m_Tgt_C_S_TRS_Stg_TOA.md); business description [`docs/mappings/035_m_Tgt_C_S_TRS_Stg_TOA.md`](../../../docs/mappings/035_m_Tgt_C_S_TRS_Stg_TOA.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA`](../../../idq-to-oracle/wf_TRS_Stage_Load_TOA/sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Stg_TOA (workflow wf_TRS_Stage_Load_TOA, its only
mapping; the daily parent workflow runs it after wf_TRS_Stage_Load_1_Ongoing).

The TIERS type-of-assistance catalogue (STG_TRS_D_LU_TOA, every row: history and expired codes included) into the
MDM lookup staging table C_S_LU_TOA (insert only, never truncated):
  -> Lkp_LOOKUP_CODE_VALUE_TOA (code type TOA, MSTR_REF_LABEL = TOA_CODE, no SRC_SYS filter, any row)
       MSTR_REF_CODE -> PKEY_SRC_OBJECT, SRC_ROWID, TOA_CD; MSTR_REF_LABEL -> TOA_LBL
  -> Lkp_LOOKUP_CODE_VALUE_MBR_PGM (code type MEMBER_PRG, MSTR_REF_LABEL = PROGRAM_CODE, any row)
       MSTR_REF_CODE -> MBR_PRG_CD (NULL when not configured)
  -> C_S_LU_TOA: EFF_STRT_DT / EFF_END_DT, TOA_DESC, CREATE_DATE = CREATE_DT, UPDATED_BY = UPDATE_USER_ID,
     LAST_UPDATE_DATE = run start, CREATOR 'admin', HUB_STATE_IND 1.
  Key = <TOA master code> (the program is not part of it).
Not a member load: the member TOA segments are m_Tgt_C_S_TRS_Pty_Rle_TOA (wf_TRS_Stage_Load_1_Ongoing), whose
TOA_FK holds the same master code (translated there by source value, here by label: docs/common_insights.md 1.21).
```

## Validations

```text
VALIDATION: none in IDQ: no router, no filter, no exception table. The only checks are the Oracle constraints of
  C_S_LU_TOA (PKEY_SRC_OBJECT NOT NULL, unique (PKEY_SRC_OBJECT, VERSION_SEQ)), which reject rows one by one.
  No begin-after-end date check (unlike m_Tgt_C_S_TRS_Pty_Rle_TOA).
```

## Bad data

```text
BAD DATA: a TOA code without a TOA master label leaves PKEY_SRC_OBJECT NULL; IDQ gets the row rejected by Oracle
  (Write_C_S_LU_TOA.bad) and logs nothing. The procedure skips these rows (Snowflake would fail the whole
  statement on the NOT NULL column). Unique keys Snowflake does not enforce are applied: C_S_LU_TOA
  (PKEY_SRC_OBJECT, VERSION_SEQ = 1), i.e. one row per TOA master code and none whose key is already in the
  table. IDQ keeps the first row read and its read has no ORDER BY, so the survivor of a code listed under
  several programs or history rows is undefined there; the procedure keeps the latest (UPDATE_DT, then
  UNIQUE_TRANS_ID, descending), as the Java and Oracle ports do. Confirm with the business (common_insights 1.22).
  Precision as IDQ: the key passes a string(10) port (cut to 10), MBR_PRG_CD a string(9) port, TOA_LBL is cut
  to 100, TOA_DESC to 250 and UPDATED_BY to 50 (target precision).
  Unfed ports written as NULL: ROWID_OBJECT (computed as the key without leading zeros but not linked), DELETED_*.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = 1 (literal '1'). PERIOD_START_DATE, PERIOD_END_DATE and PERIOD_REFERENCE_TIME are not
  linked (NULL); TIMELINE_ACTION keeps the column default 0.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `C_S_LU_TOA` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
