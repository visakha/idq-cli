# m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP &rarr; Snowflake `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`

Workflow `wf_TRS_Stage_Load_1_Ongoing`, step 6 of 14 in [`run_wf_TRS_Stage_Load_1_Ongoing.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql). Links: procedure [`sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql`](../../../idq-to-snowflake/wf_TRS_Stage_Load_1_Ongoing/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql); IDQ / CDI spec [`docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md`](../../../docs-from-idq-exports/wf_TRS_Stage_Load_1_Ongoing/mappings/m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md); business description [`docs/mappings/010_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md`](../../../docs/mappings/010_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md); Oracle port [`sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`](../../../idq-to-oracle/wf_TRS_Stage_Load_1_Ongoing/sp_ors_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql).

Drop-in replacement of the IDQ mapping in Snowflake SQL: one transaction, one set-based `INSERT` (or `INSERT ALL` for a router), `COMMIT` at the end, `ROLLBACK` and re-raise on error. It only inserts. It returns its run log line. The mapplets and rules it uses are the shared Snowflake functions of [idq-to-snowflake/common](../../../idq-to-snowflake/common/), not assumed objects.

## What it does

```text
Drop-in Snowflake replacement of IDQ mapping m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP (workflow
wf_TRS_Stage_Load_1_Ongoing).

Member-to-primary-care-provider relationships (STG_TRS_D_IN_MANAGED_CARE with a provider, one source key per
individual) into C_S_TRS_PTY_RLE_REL_PROV (insert only, never truncated):
  -> Filt_Numeric_Prov: IS_NUMBER(PROVIDER_NUM)
  -> Lookup_C_B_PTY_RLE_ALT_ID (custom lookup SQL: the TPI alternate id '006' of C21 in the MDM, latest source key
     per id) -> Exp_Build_FK: provider key = source key up to its second '|'; type 'Member PCO' when the key holds
     '|HCO', else 'Member PCP'; relationship key = member|provider|100
  -> Rout_Valid_vs_Exceptions
       Period_Start_Date_GT_Period_End_Date -> EXC_STG_BAD_REC_MEMB ('Period_Start_Date_>_Period_End_Date')
       Valid_Records (both keys, start <= end or open)
         -> MPLT_Member_PTY_RLE_REL_Consolidation (inlined) -> mplt_Pty_Rle_Rel_Timeline_Validation (inlined,
            TIMELINE) -> C_S_TRS_PTY_RLE_REL_PROV
       Default (anything else, e.g. a key missing) -> EXC_STG_BAD_REC_MEMB ('Invalid_Member' / 'Invalid_PCP')
```

## Validations

```text
VALIDATION: the provider number must be numeric (fn_snow_helper01_common) and known as a C21 TPI in the MDM; the
  begin date may not be after the end date.
```

## Bad data

```text
BAD DATA: a non-numeric provider number is dropped silently (Filt_Numeric_Prov). A missing member or provider key
  is logged as Invalid_Member / Invalid_PCP (computed code, looked-up description / type). Unfed ports written as
  NULL: CREATE_DATE (not fed into the timeline mapplet in this mapping), ROWID_OBJECT, DELETED_*, UPDATED_BY,
  CREATOR. SRC_LAST_UPD_DT = source CREATE_DT. The stored source filter PROVIDER_NUM is not null duplicates the
  custom query's WHERE. The MDM cross-reference filter ROWID_SYSTEM = 'C21' is trimmed (blank-padded MDM column).
  Unique keys Snowflake does not enforce are applied: C_S_TRS_PTY_RLE_REL_PROV (PKEY_SRC_OBJECT, VERSION_SEQ) and
  EXC_STG_BAD_REC_MEMB.
```

## MDM timeline

```text
TIMELINE (stale MDM timeline, ported as IDQ does it - same mapplet as m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem):
  DST-corrected end date (fn_snow_helper35_common + REF_DYLGHT_SVNGS_TM); every end-dated row emitted twice (closed
  version + open copy); VERSION_SEQ re-ranked per key (start ascending, end descending, NULL high);
  PERIOD_REFERENCE_TIME = end date and TIMELINE_ACTION = 2 when end dated; HUB_STATE_IND = 1 on the open row with
  VERSION_SEQ 1 (input not fed, so NULL elsewhere).
```

## Parameters

| Parameter | Type | Default | Replaces / meaning |
|---|---|---|---|
| `P_PCP_REL_TP` | VARCHAR | `'100'` | $PCP_REL_TP |

## Tables written (insert only)

| Table |
|---|
| `EXC_STG_BAD_REC_MEMB` |
| `C_S_TRS_PTY_RLE_REL_PROV` |

## Shared and helper functions called

| Function | Does |
|---|---|
| `fn_snow_helper01_common` | IDQ IS_NUMBER(): 1 / 0, NULL for NULL |
| `fn_snow_helper35_common` | mplt_DST_Correction (TIMELINE): end date corrected for daylight saving |
| `fn_snow_helper36_common` | run log line: mapping, step, row count |
| `fn_snow_helper40_common` | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE |
| `fn_snow_helper47_common` | REF_DYLGHT_SVNGS_TM (mplt_DST_Correction, TIMELINE): DST |

## Run it

```sql
CALL sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP();
```

From the CLI: `run-etl` with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` runs the whole workflow in this order.
