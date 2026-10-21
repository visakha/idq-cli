# m_Tgt_C_S_TRS_Pty_Nm &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 10 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql); IDQ / CDI spec [`idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Nm.md`](../../../idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Nm.md); business description [`docs/mappings/003_m_Tgt_C_S_TRS_Pty_Nm.md`](../../../docs/mappings/003_m_Tgt_C_S_TRS_Pty_Nm.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Nm.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Nm (workflow wf_TRS_Stage_Load_1_Ongoing).

Alias names of valid TIERS members (STG_TRS_D_CV_DC_MCI_ALIAS + STG_TRS_D_DC_ALIAS joined to STG_TRS_VALID_MEMBERS)
into C_S_TRS_PTY_NM (insert only, never truncated), name type '002' (Alias):
  -> fltr_Null_Fn_Ln: source first and last name present
  -> mplt_Name_Standardization_Trailing_Num_Removal (fn_snow_helper14_common) on the source names, then
     mplt_Name_Standardization_Indv_Member (fn_snow_helper15_common) on its output with the source prefix, suffix
     and full name
  -> srtr_Pkey (distinct) -> exp_Party_Consolidation -> srtr_TRS_Pty_Nm (distinct) -> exp_Pkey -> target
     key = PKEY_PTY || '|002|' || SEQUENCE_NUM
```

## Validations

```text
VALIDATION: the name mapplets clean the names; the mapplet's source-system input is not linked in this mapping, so
  its prefix / suffix lookups (keyed on the source system) never match: PFX_NM / SFX_NM are NULL.
```

## Bad data

```text
BAD DATA: aliases without a first or last name are dropped (fltr_Null_Fn_Ln). Unfed ports written as NULL:
  ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR, HUB_STATE_IND. C_S_TRS_PTY_NM is unique on (PKEY_SRC_OBJECT,
  VERSION_SEQ), which Snowflake does not enforce: when one alias key has several distinct versions IDQ keeps the
  first that arrives and the database rejects the rest; here the latest CREATE_DT is kept, keys already in the
  table are skipped.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it):
  * exp_Party_Consolidation ranks versions per party (v_VERSION_SEQ_RANK, v_DUP_RANK) but VERSION_SEQ_NUM is
    hard-coded to 1 (the rank is commented out) and DUP_RANK is not written.
  * PERIOD_START_DATE_OUT = IIF(v_DUP_RANK = 1, PERIOD_START_DATE, v_LAST_STRT_DATE) is a carry-forward of the
    version start date. IDQ evaluates variable ports before output ports; v_LAST_STRT_DATE is already set to the
    current PERIOD_START_DATE, so the output is always the current row's CREATE_DT (docs/common_insights.md 6).
  * PERIOD_END_DATE, PERIOD_REFERENCE_TIME are linked to unfed ports (NULL).
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_MEMBER_NAME_TYPE_CODE` | VARCHAR | `'002'` | $MemberNameTypeCode |

## Tables written (insert only)

| Table |
|---|
| `C_S_TRS_PTY_NM` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper14_common` | mplt_Name_Standardization_Trailing_Num_Removal (OBJECT) |
| `fn_snow_helper15_common` | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper43_common` | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
