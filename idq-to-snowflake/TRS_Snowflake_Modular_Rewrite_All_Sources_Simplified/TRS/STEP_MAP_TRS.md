# STEP_MAP_TRS — TRS mappings (shared multi-source framework)

Source of truth: the step numbers, step names, work tables and publish targets below are copied
from the v2 procedure headers and checkpoint calls in `mappings/` (themselves the simplified-v2
TRS rewrite). Business logic is unchanged; the only adaptation is the shared-framework control calls
(see Notes). Step names are the checkpoint `P_STEP_NAME` values, verbatim.

## Notes (apply to every mapping below)

- **Control calls:** every control call passes SOURCE first: `sp_etl_job_begin('TRS', …)`,
  `sp_etl_checkpoint('TRS', …)`, `sp_etl_job_finish('TRS', …)`, `sp_etl_job_fail('TRS', …)`
  (via a `c_source VARCHAR DEFAULT 'TRS'` variable in each procedure). Job-run-id prefixes are
  unchanged: `TRS_` for mappings, `TRS_WF_` for workflow runners.
- **Control table:** `JOB_CONTROL_ETL` (shared table with a SOURCE column), not `JOB_CONTROL_ETL_TRS`.
- **Step 5 (not listed per mapping):** `CLEANUP_PREVIOUS_RUN` — bare `DROP TABLE IF EXISTS` for that
  mapping's own work tables only, with NO checkpoint for the drops. Every run then rebuilds all
  steps from scratch; there is no step-level resume (`P_RESUME_STEP` does not exist).
- **Publish step:** the only step that writes to final targets and the only step inside an explicit
  transaction (one transaction, all targets, or nothing). Work tables are TRANSIENT, are NOT dropped
  at the end of a run, and are left standing until the next run of the same mapping cleans them up
  at its step 5. No cursors, no cleanup procedure, no end-of-run drops.
- **Step 999 / JOB_END:** on failure each mapping writes a `TERMINATING` / `FAILED` checkpoint and a
  `sp_etl_job_fail` row; it is an error terminator, not a data step, so it is not listed per mapping.
- **Publish targets** are the targets named in the publish checkpoint plus every `INSERT INTO` target
  in the publish transaction, in publish-checkpoint order where one is given.

## Workflow: wf_TRS_Stage_Load_1_Ongoing

Runner: `runners/sp_etl_run_wf_TRS_Stage_Load_1_Ongoing.sql` (run script: `runners/run_wf_TRS_Stage_Load_1_Ongoing.sql`, single runner CALL).

### 1. m_Tgt_C_S_TRS_Pty_OnGoing

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_VALID_LIST`
  - Step 20: `DQ_STANDARDISE_VALIDATE`
  - Step 30: `ROUTER_EXCEPTIONS`
  - Step 40: `DEDUP_VALID`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_PTY_S1_SRC`
  - `WRK_TRS_PTY_S2_DQ`
  - `WRK_TRS_PTY_S3_ROUTER`
  - `WRK_TRS_PTY_S4_DEDUP`
- Publish targets:
  - `C_S_TRS_PTY`
  - `C_S_TRS_PTY_RLE`
  - `STG_TRS_VALID_MEMBERS`
  - `EXC_STG_BAD_REC_MEMB`

### 2. m_Tgt_C_S_TRS_Pty_Deactivation_1

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `DEACTIVATED_INDIVIDUALS`
  - Step 20: `DEACTIVATED_PER_INDIVIDUAL`
  - Step 30: `READY_TO_PUBLISH`
  - Step 40: `PUBLISH` — publish transaction
  - Step 50: `DELETE_VALID_STAGE_NOT_PERFORMED` — checkpoint only, writes NO data (IDQ delete deliberately NOT performed; parity gap, see procedure header)
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_DEACT1_S10_DEACTV`
  - `WRK_TRS_DEACT1_S20_DEACTV_ID`
  - `WRK_TRS_DEACT1_S30_READY`
- Publish targets:
  - `STG_TRS_DEACTIVED_MEMBERS`

### 3. m_Tgt_C_S_TRS_Pty_Rle_TOA

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `TOA_SRC_RANKED`
  - Step 20: `TOA_LATEST`
  - Step 30: `TOA_KEYED`
  - Step 40: `TOA_RANKED`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_TOA_S10_RAW`
  - `WRK_TRS_TOA_S20_SRC`
  - `WRK_TRS_TOA_S30_KEYED`
  - `WRK_TRS_TOA_S40_RANKED`
- Publish targets:
  - `C_S_TRS_PTY_RLE_TOA`
  - `EXC_STG_BAD_REC_MEMB`

### 4. m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_RELATIONSHIPS`
  - Step 20: `KEYED`
  - Step 30: `ROUTER_EXCEPTIONS`
  - Step 40: `CONSOLIDATED`
  - Step 50: `PREPARED`
  - Step 60: `TIMELINE`
  - Step 70: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_REL1_S1_SRC`
  - `WRK_TRS_REL1_S2_KEYED`
  - `WRK_TRS_REL1_S3_ROUTER`
  - `WRK_TRS_REL1_S4_CONSOL`
  - `WRK_TRS_REL1_S5_PREP`
  - `WRK_TRS_REL1_S6_TIMELINE`
- Publish targets:
  - `C_S_TRS_PTY_RLE_REL`
  - `EXC_STG_BAD_REC_MEMB`

### 5. m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `MIN_PK`
  - Step 20: `REL_SRC`
  - Step 30: `KEYED_REL`
  - Step 40: `XREF_ONE`
  - Step 50: `READY_TO_PUBLISH`
  - Step 60: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_RELDEACT_S10_MINPK`
  - `WRK_TRS_RELDEACT_S20_SRC`
  - `WRK_TRS_RELDEACT_S30_KEYED`
  - `WRK_TRS_RELDEACT_S40_XREF`
  - `WRK_TRS_RELDEACT_S50_READY`
- Publish targets:
  - `STG_TRS_DEACTIVATED_RELATIONSHIPS`

### 6. m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_MANAGED_CARE`
  - Step 20: `KEYED`
  - Step 30: `ROUTER_EXCEPTIONS`
  - Step 40: `CONSOLIDATED`
  - Step 50: `PREPARED`
  - Step 60: `TIMELINE`
  - Step 70: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_REL2_S1_SRC`
  - `WRK_TRS_REL2_S2_KEYED`
  - `WRK_TRS_REL2_S3_ROUTER`
  - `WRK_TRS_REL2_S4_CONSOL`
  - `WRK_TRS_REL2_S5_PREP`
  - `WRK_TRS_REL2_S6_TIMELINE`
- Publish targets:
  - `C_S_TRS_PTY_RLE_REL_PROV`
  - `EXC_STG_BAD_REC_MEMB`

### 7. m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_CASE_DELTA`
  - Step 20: `PHONE_SLOTS`
  - Step 30: `PHONES_CHECKED`
  - Step 40: `PHONES`
  - Step 50: `PHN_VERSIONS`
  - Step 60: `EMAILS_CHECKED`
  - Step 70: `EADDR_VERSIONS`
  - Step 80: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_PHN_S1_SRC`
  - `WRK_TRS_PHN_S2_SLOTS`
  - `WRK_TRS_PHN_S3_CHECKED`
  - `WRK_TRS_PHN_S4_PHONES`
  - `WRK_TRS_PHN_S5_VERSIONS`
  - `WRK_TRS_PHN_S6_EMAILS`
  - `WRK_TRS_PHN_S7_VERSIONS`
- Publish targets:
  - `C_S_TRS_PTY_RLE_PHN`
  - `C_S_TRS_PTY_RLE_EADDR`
  - `EXC_STG_BAD_REC_MEMB`

### 8. m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `DAILY_INDV`
  - Step 20: `VALID_SRC`
  - Step 30: `UNPIVOT_SWITCHES`
  - Step 40: `FILTERED_ATTRS`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_MNGSW_S10_DAILY`
  - `WRK_TRS_MNGSW_S20_SRC`
  - `WRK_TRS_MNGSW_S30_NORM`
  - `WRK_TRS_MNGSW_S40_ATTRS`
- Publish targets:
  - `C_S_TRS_PTY_MNG_ATTR`

### 9. m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `PAYEE_CASE_ROWS`
  - Step 20: `VALID_SRC`
  - Step 30: `KEYED`
  - Step 40: `AGG_DEDUP`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_MNGAR_S10_PAYEE`
  - `WRK_TRS_MNGAR_S20_SRC`
  - `WRK_TRS_MNGAR_S30_KEYED`
  - `WRK_TRS_MNGAR_S40_AGG`
- Publish targets:
  - `C_S_TRS_PTY_MNG_ATTR`

### 10. m_Tgt_C_S_TRS_Pty_Nm

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `ALIAS_SRC`
  - Step 20: `NAMED_FILTERED`
  - Step 30: `STANDARDISED`
  - Step 40: `DEDUP_KEYED`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_NM_S10_SRC`
  - `WRK_TRS_NM_S20_NAMED`
  - `WRK_TRS_NM_S30_STD`
  - `WRK_TRS_NM_S40_DEDUP`
- Publish targets:
  - `C_S_TRS_PTY_NM`

### 11. m_Tgt_C_S_TRS_Pty_Rle_Alt_Id

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_DEDUP`
  - Step 20: `SSN_VALIDATED`
  - Step 30: `NORMALIZED`
  - Step 40: `ROUTED`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_ALT_S1_SRC`
  - `WRK_TRS_ALT_S2_SSN`
  - `WRK_TRS_ALT_S3_NORM`
  - `WRK_TRS_ALT_S4_ROUTED`
- Publish targets:
  - `C_S_TRS_PTY_RLE_ALT_ID`
  - `EXC_STG_BAD_REC_MEMB`

### 12. m_Tgt_C_S_TRS_Pty_Rle_Pln

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `MANAGED_CARE_SRC`
  - Step 20: `PLAN_TRANSLATED`
  - Step 30: `RANKED`
  - Step 40: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_PLN_S10_SRC`
  - `WRK_TRS_PLN_S20_PLANNED`
  - `WRK_TRS_PLN_S30_RANKED`
- Publish targets:
  - `C_S_TRS_PTY_RLE_PLN`
  - `EXC_STG_BAD_REC_MEMB`

### 13. m_Tgt_C_S_TRS_Addr_1

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Addr_1.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_DISTINCT_ADDR`
  - Step 20: `DERIVED_ADDR_LINES`
  - Step 30: `ADDR_VALIDATION`
  - Step 40: `READY_TO_PUBLISH`
  - Step 50: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_ADDR1_S10_SRC`
  - `WRK_TRS_ADDR1_S20_DERIVED`
  - `WRK_TRS_ADDR1_S30_VALIDATED`
  - `WRK_TRS_ADDR1_S40_READY`
- Publish targets:
  - `STG_TRS_D_UNQ_ADDR`

### 14. m_Tgt_C_S_TRS_Addr_2

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Addr_2.sql`
- Workflow: `wf_TRS_Stage_Load_1_Ongoing`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `ADDR_DEDUP`
  - Step 20: `SRC_VALIDATED_JOIN`
  - Step 30: `KEYED_ADDR`
  - Step 40: `SCORED_VERSIONED`
  - Step 50: `READY_TO_PUBLISH`
  - Step 60: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_ADDR2_S10_DEDUP`
  - `WRK_TRS_ADDR2_S20_SRC`
  - `WRK_TRS_ADDR2_S30_KEYED`
  - `WRK_TRS_ADDR2_S40_SCORED`
  - `WRK_TRS_ADDR2_S50_READY`
- Publish targets:
  - `DQM_ADDRESS`
  - `C_S_TRS_PTY_RLE_ADDR`
  - `EXC_STG_BAD_REC_MEMB`

## Workflow: wf_TRS_Stage_Load_TOA

Runner: `runners/sp_etl_run_wf_TRS_Stage_Load_TOA.sql` (run script: `runners/run_wf_TRS_Stage_Load_TOA.sql`, single runner CALL).

### 15. m_Tgt_C_S_TRS_Stg_TOA

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA.sql`
- Workflow: `wf_TRS_Stage_Load_TOA`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `CATALOGUE_KEYED`
  - Step 20: `SURVIVOR_PER_KEY`
  - Step 30: `PUBLISH` — publish transaction
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_TRS_LUTOA_S10_KEYED`
  - `WRK_TRS_LUTOA_S20_FINAL`
- Publish targets:
  - `C_S_LU_TOA`
