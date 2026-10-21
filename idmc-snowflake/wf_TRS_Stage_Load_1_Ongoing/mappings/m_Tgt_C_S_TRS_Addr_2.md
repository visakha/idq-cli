# m_Tgt_C_S_TRS_Addr_2 &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Addr_2`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 14 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Addr_2.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Addr_2.sql); IDQ / CDI spec [`idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Addr_2.md`](../../../idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Addr_2.md); business description [`docs/mappings/012_m_Tgt_C_S_TRS_Addr_2.md`](../../../docs/mappings/012_m_Tgt_C_S_TRS_Addr_2.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Addr_2`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Addr_2.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Addr_2 (workflow wf_TRS_Stage_Load_1_Ongoing).

Part 2 of the TIERS address load: the individual addresses of the extract (latest create per individual / address
type / case / EDG) joined to the pre-validated unique addresses of m_Tgt_C_S_TRS_Addr_1 (STG_TRS_D_UNQ_ADDR) and to
the valid members:
  -> Write_DQM_ADDRESS (every row)
  -> lkp_Address_Type (V_LOOKUP_CODE_VALUE ADDR_TP, 'TRS') -> exp_Score_and_Exception_details
  -> rtr_Good_vs_Exception_Pty_Records
       Good ('100')     -> exp_Address_Hold -> srt_Party_Role_Addr_By_PKey_Beg_Date
                           -> exp_Party_Role_Address_Attribute_Hold (VERSION_SEQ) -> C_S_TRS_PTY_RLE_ADDR
       Exception ('40') -> EXC_STG_BAD_REC_MEMB ('Invalid_Address', looked-up code)
       Default          -> not linked (the score is always '40' or '100')
```

## Validations

```text
VALIDATION: address score (fn_snow_helper05_common) on the master address type, the mailability score and the
  AddressDoctor match code of part 1 (VLDTN_MSG); an address type that does not translate scores '40'.
```

## Bad data

```text
BAD DATA: an exception address is not loaded, only logged, with the looked-up code (NULL when 'Invalid_Address' is
  not configured, docs/common_insights.md section 3). The source's "select distinct" flag is ignored by IDQ when
  custom SQL is used, so it is not applied here either. Unfed ports written as NULL: ROWID_OBJECT, DELETED_*,
  UPDATED_BY, HUB_STATE_IND, USG_TP, CRDNT_SYS, PSTL_BRCD, RGN_CD, CREATOR, CREATE_DATE, LCTN_CRDNT_DESC (sorter
  port without input). Unique keys Snowflake does not enforce are applied: C_S_TRS_PTY_RLE_ADDR (PKEY_SRC_OBJECT,
  VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it; one of the three places where it is real):
  * VERSION_SEQ is a running number per role-address key in (key, SRC_LAST_UPDATE_DATE desc, EFF_END_DT desc,
    EFF_BEGIN_DT desc; NULL high) order - every row is written, numbered 1, 2, 3, ... within the key.
  * SRC_ROWID = key || '|' || VERSION_SEQ.
  * PERIOD_REFERENCE_TIME = run start when EFF_END_DT is set.
  * PERIOD_END_DATE / EFF_END_DT = mplt_Date_Greater_Than_Fifty_Years(EFF_END_DT) (fn_snow_helper21_common): IDQ
    compares the year difference as TEXT with '50', so end dates more than 50 years away AND end dates 6 to 10
    years away become NULL (open) - docs/common_insights.md 1.15.
  * PERIOD_START_DATE / EFF_STRT_DT = EFF_BEGIN_DT.
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_MEMBER_ROLE_TYPE` | VARCHAR | `'Member'` | $Member_Role_Type |
| `P_MEMBER_HIERARCHY_CODE` | VARCHAR | `'Member'` | $Member_Hierarchy_Code |
| `P_MEMBER_HM_REL_TP_CD` | VARCHAR | `'Member Addr'` | $Member_HM_REL_TP_CD |

## Tables written (insert only)

| Table |
|---|
| `DQM_ADDRESS` |
| `C_S_TRS_PTY_RLE_ADDR` |
| `EXC_STG_BAD_REC_MEMB` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper05_common` | address score of exp_Score_and_Exception_details: '40' exception / '100' |
| `fn_snow_helper06_common` | address issue text of exp_Score_and_Exception_details (Addr_Issue_Desc) |
| `fn_snow_helper07_common` | exp_Address_Hold line 1: empty line 1 replaced by line 2 |
| `fn_snow_helper08_common` | exp_Address_Hold line 2: cleared when it repeats the held line 1 |
| `fn_snow_helper21_common` | mplt_Date_Greater_Than_Fifty_Years: the date, or NULL |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Addr_2();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
