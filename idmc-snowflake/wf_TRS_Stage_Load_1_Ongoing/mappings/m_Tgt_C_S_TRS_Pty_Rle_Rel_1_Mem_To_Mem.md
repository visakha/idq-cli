# m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 4 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql); IDQ / CDI spec [`idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md`](../../../idmc/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md); business description [`docs/mappings/009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md`](../../../docs/mappings/009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (workflow
wf_TRS_Stage_Load_1_Ongoing).

Member-to-member relationships (STG_TRS_D_DC_RELATIONSHIPS; both sides valid members, one source key per
individual) into C_S_TRS_PTY_RLE_REL (insert only, never truncated):
  -> Lookup_V_LOOKUP_CODE_VALUE (code type PTY_REL, 'TRS') + exp_Build_FK -> rtr_AltId_Exp
       Invalid_Main_Alt_Id (no main party key)  -> EXC_STG_BAD_REC_MEMB ('Invalid_Member')
       Invalid_Ref_Alt_Id  (no related key)     -> EXC_STG_BAD_REC_MEMB ('Invalid_Ref_Member')
       Invalid_Lookup      (type untranslated)  -> EXC_STG_BAD_REC_MEMB ('Invalid_Rel_Type', looked-up code)
       Period_Start_Dt_GT_Period_End_Date       -> EXC_STG_BAD_REC_MEMB ('Period_Start_Date_>_Period_End_Date')
       Default (none of the above)
         -> MPLT_Member_PTY_RLE_REL_Consolidation (inlined, set level): type present, distinct on
            (key, end date, start date), one row per (key, end, start)
         -> Exp_safe_C_S_TRS_PTY_RLE_REL
         -> mplt_Pty_Rle_Rel_Timeline_Validation (inlined, TIMELINE, see below) -> C_S_TRS_PTY_RLE_REL

docs/common_insights.md section 8):
  mplt_Pty_Rle_Rel_Timeline_Validation
  1. mplt_DST_Correction (fn_snow_helper35_common + REF_DYLGHT_SVNGS_TM): the end date moves forward one hour when
     start = end, or when end + 2 hours is a daylight-saving change.
  2. rtr_Active_Records + union_All_Records: open rows (no end date) pass once; every END-DATED row is emitted
     TWICE - the closed version (End_Dated_Records) and an open copy with the end date removed
     (New_Active_Records).
  3. SRT_PKEY_FOR_RANK + exp_RANK: VERSION_SEQ is re-numbered per key in (start date ascending, end date
     descending, NULL high) order.
  4. exp_Stage_Output_Attributes: PERIOD_REFERENCE_TIME = end date and TIMELINE_ACTION = 2 when end dated;
     LAST_UPDATE_DATE = run start; HUB_STATE_IND forced to 1 on the open row with VERSION_SEQ 1 (the input
     HUB_STATE_IND is not fed, so all other rows get NULL).
```

## Validations

```text
VALIDATION: both members must be valid TRS members (STG_TRS_VALID_MEMBERS), the relationship type must translate
  (V_LOOKUP_CODE_VALUE PTY_REL), and the begin date may not be after the end date.
```

## Bad data

```text
BAD DATA: a failing relationship is not loaded, only logged; a row can match several exception groups and is then
  logged once per group. 'Invalid_Rel_Type' writes the looked-up code (NULL when not configured). Unfed ports
  written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR. Unique keys Snowflake does not enforce are
  applied: C_S_TRS_PTY_RLE_REL (PKEY_SRC_OBJECT, VERSION_SEQ) and EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it; here the timeline changes the ROW SET, not only column values,
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_INDV_ID_ALT_ID_TP` | VARCHAR | `'007'` | $INDV_ID_ALT_ID_TP (substituted into the source SQL) |

## Tables written (insert only)

| Table |
|---|
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_TRS_PTY_RLE_REL` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper35_common` | mplt_DST_Correction (TIMELINE): end date corrected for daylight saving |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper41_common` | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
| `fn_snow_helper47_common` | REF_DYLGHT_SVNGS_TM (mplt_DST_Correction, TIMELINE): DST |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
