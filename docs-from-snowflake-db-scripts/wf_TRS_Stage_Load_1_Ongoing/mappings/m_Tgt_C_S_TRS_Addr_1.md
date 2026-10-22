# m_Tgt_C_S_TRS_Addr_1 &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Addr_1`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 13 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Addr_1.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Addr_1.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Addr_1.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Addr_1.md); business description [`docs/mappings/011_m_Tgt_C_S_TRS_Addr_1.md`](../../../docs/mappings/011_m_Tgt_C_S_TRS_Addr_1.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Addr_1`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Addr_1.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Addr_1 (workflow wf_TRS_Stage_Load_1_Ongoing).

Part 1 of the TIERS address load: every UNIQUE address of the daily extract (STG_TRS_D_INDV_ADDR, distinct on the
address parts) goes through the address validator once (about a tenth of the volume), and every result, good or
bad, is written to the intermediate table STG_TRS_D_UNQ_ADDR (insert only, never truncated).
m_Tgt_C_S_TRS_Addr_2 joins it back to the individuals.
  -> lkp_Addr_Street_Type (STG_TRS_CD_REF) + exp_TRS_Addr_Derivation:
       line 1 = street number, fraction, direction (EA/NO/SO/WE abbreviated to the first letter, any case), street
                name, street type description
       line 2 = dwelling type, apartment number, address line
       zip    = zip5 || '-' || zip4
  -> mplt_Global_Addr_Validation (fn_snow_helper34_common, with its lkp_State_Cd and lkp_ref_MatchCode_Desc)
     -> Expression -> Write_STG_TRS_D_UNQ_ADDR
```

## Validations

```text
VALIDATION: the address validator (pass-through stand-in for AddressDoctor, README "Address validation"); the
  score is computed later, in m_Tgt_C_S_TRS_Addr_2.
```

## Bad data

```text
BAD DATA: the scrub rules clean the result lines; the derived source lines are kept in SRC_ADDR_LN_*. SRC_COUNTY is
  linked to an unfed port (NULL). STG_TRS_D_UNQ_ADDR has primary key ADDR_ID, which Snowflake does not enforce;
  IDQ truncates the table first, this code does not, so an address already validated in an earlier run is not
  written again (the existing row is reused by part 2).
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
| `STG_TRS_D_UNQ_ADDR` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper34_common` | mplt_Global_Addr_Validation (pass-through validator, OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper46_common` | ref_MatchCode_Desc (mplt_Global_Addr_Validation): MATCH_CODE -> DESCRIPTION |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Addr_1();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
