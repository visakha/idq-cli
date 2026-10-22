# m_Tgt_C_S_ECI_Pty_Addr &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr`

Workflow `wf_ECI_Stage_Load`, step 8 of 9 in [`run_wf_ECI_Stage_Load.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql`](../../../idq-to-snowflake/wf_ECI_Stage_Load/sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Addr.md`](../../../docs-from-idq-exports/wf_ECI_Stage_Load/mappings/m_Tgt_C_S_ECI_Pty_Addr.md); business description [`docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md`](../../../docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md); Oracle port [`sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr`](../../../idq-to-oracle/wf_ECI_Stage_Load/sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_ECI_Pty_Addr (workflow wf_ECI_Stage_Load).

Validates the ECI child and family addresses (V_ECI_ETL_SRC_FAMILY_ADDRESS) with the global address mapplet and
loads the good ones into C_S_ECI_PTY_RLE_ADDR (insert only, never truncated):
  Read_V_ECI_ETL_SRC_FAMILY_ADDRESS -> lkp_Address_Type (V_LOOKUP_CODE_VALUE ADDR_TP)
    -> Fil_Inactive_recs: party not in STG_ECI_PTY_INACTIVE_STS
    -> mplt_Global_Addr_Validation (fn_snow_helper34_common, with its lkp_State_Cd and lkp_ref_MatchCode_Desc)
    -> exp_Score_and_Exception_details -> Write_DQM_ADDRESS        (every active address, before routing)
    -> rtr_Good_vs_Exception_Pty_Records
         Good      (Score = '100') -> exp_Address_Hold -> Write_C_S_ECI_PTY_RLE_ADDR
         Exception (Score = '40')  -> write_ECI_Exc_Member_Rec (EXC_STG_BAD_REC_MEMB, 'Invalid_Address')
         Default                   -> not linked (Score is always '40' or '100', so no row reaches it)
```

## Validations

```text
VALIDATION: Score '40' (fn_snow_helper05_common): address type not physical mail (002) and mailability <= '3';
  physical mail with mailability < '3' and a match code starting I / N; or an address type that does not
  translate. Comparisons are on strings, as in IDQ. The address validator is the pass-through stand-in for
  AddressDoctor (README, "Address validation"): mailability and match code are NULL, so every address with a
  known type scores '100'.
```

## Bad data

```text
BAD DATA: an exception address is not loaded, only logged, with the hard-coded description 'Invalid Address per
  Address Doctor' and type 'Bad Value' (no EXC_LOOKUP_CODE_VALUE lookup in this mapping). The scrub rules clean
  the result lines; the source lines are kept in SRC_ADDR_LN_*. Ports linked to targets but fed by nothing in IDQ
  are written as NULL (ROWID_OBJECT, DELETED_*, CREATOR, PSTL_BRCD, RGN_CD, LCTN_CRDNT_DESC, EFF_END_DT, the
  exception PERIOD_END_DATE, and FLR_NUM: the router port Sub_buildingNumber has no input link). Unique keys
  Snowflake does not enforce are applied: C_S_ECI_PTY_RLE_ADDR (PKEY_SRC_OBJECT, VERSION_SEQ) and
  EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it):
  * VERSION_SEQ = 1 (exp_Stage_Target_Party_Role_Addr_Attributes.VERSION_SEQ_NUM).
  * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set; EFF_END_DT is not linked in IDQ, so it is NULL.
  * PERIOD_START_DATE / EFF_STRT_DT = source LAST_UPDATE_DATE; EFF_END_DT NULL.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_MEMBER_HIERARCHY_CODE` | VARCHAR | `'Member'` | $Member_Hierarchy_Code |
| `P_MEMBER_HM_REL_TP_CD` | VARCHAR | `'Member Addr'` | $Member_HM_REL_TP_CD |

## Tables written (insert only)

| Table |
|---|
| `DQM_ADDRESS` |
| `C_S_ECI_PTY_RLE_ADDR` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper04_common` | IDQ TO_DECIMAL(value, scale): non-numeric 0, NULL NULL |
| `fn_snow_helper05_common` | address score of exp_Score_and_Exception_details: '40' exception / '100' |
| `fn_snow_helper06_common` | address issue text of exp_Score_and_Exception_details (Addr_Issue_Desc) |
| `fn_snow_helper07_common` | exp_Address_Hold line 1: empty line 1 replaced by line 2 |
| `fn_snow_helper08_common` | exp_Address_Hold line 2: cleared when it repeats the held line 1 |
| `fn_snow_helper34_common` | mplt_Global_Addr_Validation (pass-through validator, OBJECT) |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper46_common` | ref_MatchCode_Desc (mplt_Global_Addr_Validation): MATCH_CODE -> DESCRIPTION |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
