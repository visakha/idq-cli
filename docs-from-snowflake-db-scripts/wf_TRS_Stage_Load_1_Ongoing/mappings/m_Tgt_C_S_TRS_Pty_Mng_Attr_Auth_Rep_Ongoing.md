# m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 9 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md); business description [`docs/mappings/002_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md`](../../../docs/mappings/002_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (workflow
wf_TRS_Stage_Load_1_Ongoing). Runs after m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw and APPENDS to C_S_TRS_PTY_MNG_ATTR.

Authorized-representative flag ('Auth_Rep_Flag' = 'Y') of valid TIERS members whose case has a verified,
sent authorized representative (custom SQL: six union branches over the payee / case / EDG delta tables):
  -> srtr_Indv_Id (INDV_ID, EFF_BEGIN_DT) -> exp_Rank -> srtr_Rank (distinct) -> exp_Pkey_Generation
  -> agg_Dedup_TRS_Pty_Mng_Attr: one row per key (INDV_ID || '|Auth_Rep_Flag'), PERIOD_END_DATE = MAX(EFF_END_DT),
     every other port from the last row of the group
```

## Validations

```text
VALIDATION: none (no rule runs here); the verification codes CS / FH / LD / OA and SENT_AUTHREP_SW = 'Y' select the
  cases.
```

## Bad data

```text
BAD DATA: C_S_TRS_PTY_MNG_ATTR is unique on (PKEY_SRC_OBJECT, VERSION_SEQ), which Snowflake does not enforce: a key
  already in the table is skipped (the aggregator already gives one row per key in the run).
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it):
  * exp_Rank.VERSION_SEQ_NUM is hard-coded to 1 and written to VERSION_SEQ.
  * srtr_Rank is a distinct re-sort on INDV_ID around exp_Rank (kept: the DISTINCT below).
  * PERIOD_START_DATE = EFF_BEGIN_DT of the last row, PERIOD_END_DATE = MAX(EFF_END_DT) per key.
  Last row per key = latest EFF_BEGIN_DT (srtr_Indv_Id order, NULL high), assuming the key-only re-sort keeps it.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_ATTR_TP_AUTH_REP` | VARCHAR | `'Auth_Rep_Flag'` | $ATTR_TP_AUTH_REP |

## Tables written (insert only)

| Table |
|---|
| `C_S_TRS_PTY_MNG_ATTR` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
