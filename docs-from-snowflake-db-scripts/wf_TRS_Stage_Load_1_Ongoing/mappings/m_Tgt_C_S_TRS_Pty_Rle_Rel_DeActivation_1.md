# m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 5 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 (workflow
wf_TRS_Stage_Load_1_Ongoing).

Logs TIERS relationships that were deactivated (STG_TRS_D_DC_RELATIONSHIPS_A, both sides valid members) so a
later process can soft-delete them in the MDM:
  -> Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL) + Exp_Gen_PKEY: key = member|ref member|master type
  -> Lookup_STG_TRS_DEACTIVATED_RELATIONSHIPS (unprocessed rows only) and Lkp_C_B_PTY_RLE_REL_XREF (custom lookup
     SQL: per MDM cross-reference the record count, merge / master / soft-delete flags, lowest ROWID_XREF of the key)
  -> Fil_New_Deactivations: not yet logged as unprocessed AND present in the MDM (a cross-reference exists)
  -> STG_TRS_DEACTIVATED_RELATIONSHIPS (insert; PROCESSED_YN is not linked - left to the column default)
```

## Validations

```text
VALIDATION: none (no rule runs here); the relationship must exist in the MDM (C_B_PTY_RLE_REL_XREF).
```

## Bad data

```text
BAD DATA: the mapping description also mentions removing relationships from a valid list; the IDQ mapping has no
  such target (docs/common_insights.md 1.10). An untranslated relationship type gives a key ending in '|', which
  finds no cross-reference and is dropped by the filter.
```

## MDM timeline

```text
TIMELINE: none.
```

## Parameters

None.

## Tables written (insert only)

| Table |
|---|
| `STG_TRS_DEACTIVATED_RELATIONSHIPS` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
