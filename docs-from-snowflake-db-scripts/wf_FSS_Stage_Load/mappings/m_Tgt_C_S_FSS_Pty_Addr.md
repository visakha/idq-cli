# m_Tgt_C_S_FSS_Pty_Addr &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr`

Workflow `wf_FSS_Stage_Load`, step 3 of 6 in [`run_wf_FSS_Stage_Load.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr.sql`](../../../idq-to-snowflake/wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Addr.md`](../../../docs-from-idq-exports/wf_FSS_Stage_Load/mappings/m_Tgt_C_S_FSS_Pty_Addr.md); business description [`docs/mappings/021_m_Tgt_C_S_FSS_Pty_Addr.md`](../../../docs/mappings/021_m_Tgt_C_S_FSS_Pty_Addr.md); Oracle port [`sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr`](../../../idq-to-oracle/wf_FSS_Stage_Load/sp_ors_main_m_Tgt_C_S_FSS_Pty_Addr.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_FSS_Pty_Addr (workflow wf_FSS_Stage_Load; copied from the
ECI address mapping).

Validates the FSS client addresses (V_FSS_ETL_SRC, capture action not 'D') and loads the good ones into
C_S_FSS_PTY_RLE_ADDR (insert only, never truncated):
  -> Fil_Inactive_recs: party (PTY_SRC_KEY) not in STG_FSS_PTY_INACTIVE_STS
  -> mplt_Global_Addr_Validation (fn_snow_helper34_common), zip without extension
  -> Write_DQM_ADDRESS (every active address)
  -> rtr_Good_vs_Exception_Pty_Records: Good ('100') -> C_S_FSS_PTY_RLE_ADDR; Exception ('40') -> EXC row
```

## Validations

```text
VALIDATION: the address type is the constant '002' (physical mail), so the score (fn_snow_helper05_common)
  depends only on the mailability score and the match code; with the pass-through validator both are NULL and
  every address scores '100'.
```

## Bad data

```text
BAD DATA: an exception address is not loaded, only logged ('Invalid Address per Address Doctor', 'Bad Value').
  DQM_ADDRESS.PTY_SRC_KEY adds the family 'F' only for SOURCE_TYPE 'FSS_FAMILY', which never occurs (copied from
  ECI, docs/common_insights.md section 10). Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, CREATOR, USG_TP,
  LCTN_CRDNT_DESC, PSTL_BRCD, RGN_CD, SRC_PSTL_CD_EXT, ADDRESS_ZIP_EXT, PERIOD_END_DATE, FLR_NUM (router port
  without input link). Unique keys Snowflake does not enforce are applied: C_S_FSS_PTY_RLE_ADDR (PKEY_SRC_OBJECT,
  VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE: VERSION_SEQ = 1; PERIOD_START_DATE = DT_CREATED, EFF_STRT_DT = DT_LAST_UPDATE; EFF_END_DT and
  PERIOD_REFERENCE_TIME are linked to an unfed port (NULL).
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
| `C_S_FSS_PTY_RLE_ADDR` |
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
CALL sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
