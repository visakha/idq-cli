# Step Map — All Sources (combined)

Concatenation of the six per-source step maps. Each source section is authoritative for that source.

---
## TRS

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

---
## ECI

# STEP_MAP_ECI — wf_ECI_Stage_Load (modular rewrite, simplified v2 style)

Install: database `MDM_ETL_ECI`, schema `ECI_ETL_WRK`. All table names in
the procedures are unqualified. Every procedure appends `P_JOB_RUN_ID
VARCHAR DEFAULT NULL` after its original parameters, in the same order.
Every procedure starts with step 5 `CLEANUP_PREVIOUS_RUN` (bare
`DROP TABLE IF EXISTS` for that mapping's work tables only, no checkpoint
call for drops), writes a checkpoint per staged step, publishes in the
only transaction, and leaves its work tables standing afterwards.
Restart is mapping-level only: a new run cleans up at step 5 and runs
every step from scratch. No `P_RESUME_STEP`, no resume guards, no
end-of-run drops, no cleanup procedure. All loads are insert-only
(no `TRUNCATE` / `DELETE` of targets), exactly as in the originals.

Runner order (identical to the original `run_wf_ECI_Stage_Load.sql`):
Validation, Pty, Reactivation_D_Family_Addr, Reactivation_D_Family_Phn,
Reactivation_D_Medicaid, Pty_Rle_Alt_Id, Pty_Rle_Phn_And_EAddr, Pty_Addr,
Pty_Rle_Rel. Runner: `sp_etl_run_wf_ECI_Stage_Load` (see `runners/`).

## 1. m_Tgt_C_S_ECI_Pty_Validation — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation`

Checks every child/family delta party and maintains the deactivation
list every later mapping filters on. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | SRC_DELTA_PARTIES | `WRK_ECI_VAL_S10_SRC` | Child + family delta rows, party key, 10-character full name |
| 20 | ENRICHED_STD_NAMES | `WRK_ECI_VAL_S20_ENRICHED` | Status / hub / duplicate / family lookups + standardised names |
| 30 | ROUTED_GROUPS | `WRK_ECI_VAL_S30_ROUTED` | Blank-name / deactivation / reactivation groups, exception descriptions, `uq_exc_name` flag |
| 40 | PUBLISH | — (transaction) | 4 inserts, original order |

Publish targets: `EXC_STG_BAD_REC_MEMB` (blank-name exceptions),
`STG_ECI_PTY_INACTIVE_LOG` (deactivation + reactivation log rows),
`STG_ECI_PTY_INACTIVE_STS` (new deactivation status rows only).

Preserved quirks: full name cut at 10 characters; no prefix/suffix passed
to name standardisation; the IDQ delete of the inactive-status table is
not performed; exception description/type from the exception catalogue
(NULL when unconfigured).

## 2. m_Tgt_C_S_ECI_Pty — `sp_snow_main_m_Tgt_C_S_ECI_Pty`

Loads active child/family parties and logs demographic exceptions.
Original parameters: `P_PTY_BO_CLASS_CD_MEMBER` ('Indv'),
`P_RLE_BO_CLASS_CD_MEMBER` ('Member').

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 5 work tables below |
| 10 | SRC_DELTA_PARTIES | `WRK_ECI_PTY_S10_SRC` | Child + family delta rows, party key, party type, source full name |
| 20 | ACTIVE_PARTIES | `WRK_ECI_PTY_S20_ACTIVE` | Active parties only (no deactivation status) |
| 30 | DQ_RULES | `WRK_ECI_PTY_S30_DQ` | Name standardisation, gender, birth date, ethnicity, race indicators, language |
| 40 | DQ_EXCEPTIONS_RESOLVED | `WRK_ECI_PTY_S40_DQ2` | Standardised fields unpacked, every exception code/description/type resolved |
| 50 | ROUTED_READY | `WRK_ECI_PTY_S50_READY` | Router groups, party/role keys, insert-only guards |
| 60 | PUBLISH | — (transaction) | 7 inserts, original order |

Publish targets: `C_S_ECI_PTY`, `C_S_ECI_PTY_RLE`, `EXC_STG_BAD_REC_MEMB`
(gender, birth date, ethnicity, race, language — in that order).

Preserved quirks: exception rows carry the literal mapping name
`m_Tgt_C_S_ECI_Pty_OnGoing`; the stored filter on five child ids is
ignored (not part of the custom query); the stored inactive-filter
comment means active parties are kept; `VERSION_SEQ` = 1; duplicate rank
and demographics MD5 are not computed (IDQ does not write them);
party `PERIOD_START_DATE` = source `DATE_MODIFIED`, role
`PERIOD_START_DATE` = `DATE_CREATED`; an exception never rejects a party
(a future birth date loads as NULL); ethnicity/race/language exceptions
are child rows only.

## 3. m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr — `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`

Moves the latest history address row of each reactivated family into the
delta table. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | LATEST_HISTORY_ROWS | `WRK_ECI_RFA_S10_LATEST` | Latest history row per address of reactivated families |
| 20 | KEEP_NEW_ONLY | `WRK_ECI_RFA_S20_KEEPNEW` | Latest rows not already in the delta table |
| 30 | PUBLISH | — (transaction) | 1 insert |

Publish target: `STG_ECI_D_FAMILY_ADDRESS`.

FLAGGED SPLIT: the original is a single INSERT with no CTE chain, so
this is the closest sensible split (latest rows, then keep-new filter,
then publish), not a CTE-boundary split. The keep-new filter is
evaluated in step 20, before any insert, so it still sees the delta
table as it was before the run, as in the original.

## 4. m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn — `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`

Moves the latest history phone row of each reactivated family into the
delta table. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | LATEST_HISTORY_ROWS | `WRK_ECI_RFP_S10_LATEST` | Latest history row per phone record of reactivated families |
| 20 | KEEP_NEW_ONLY | `WRK_ECI_RFP_S20_KEEPNEW` | Latest rows not already in the delta table |
| 30 | PUBLISH | — (transaction) | 1 insert |

Publish target: `STG_ECI_D_FAMILY_PHONE`.

FLAGGED SPLIT: as §3 — the original is a single INSERT with no CTE
chain; closest sensible split (latest rows, keep-new filter, publish).

## 5. m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid — `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`

Moves the latest history Medicaid row of each reactivated child into the
delta table. Original parameters: `P_TEST_LOOKUP_RESULT` ('N').

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | LATEST_HISTORY_ROWS | `WRK_ECI_RFM_S10_LATEST` | Latest history row per Medicaid record of reactivated children, plus the delta-table lookup key (`LKP_ID_MEDICAID`) |
| 20 | KEEP_NEW_ONLY | `WRK_ECI_RFM_S20_KEEPNEW` | Rows passing the keep-new filter, one row per Medicaid id |
| 30 | PUBLISH | — (transaction) | 1 insert |

Publish target: `STG_ECI_D_MEDICAID`.

FLAGGED SPLIT: as §3 — the original is a single INSERT with no CTE
chain; closest sensible split (latest rows + lookup, keep-new filter +
rank, publish).

PRESERVED DEFECT: with the default `P_TEST_LOOKUP_RESULT` = 'N' the
keep-new filter tests the source `ID_MEDICAID`, which is never NULL, so
the mapping writes no rows, exactly as IDQ does. Passing 'Y' tests the
lookup result instead (records not yet in the delta table). The runner
passes 'N' (the original default).

## 6. m_Tgt_C_S_ECI_Pty_Rle_Alt_Id — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`

Loads alternate ids (child ECI id 018, child SSN 004, Medicaid number
002, family ECI id 019); invalid SSNs/Medicaid ids are only logged.
Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ALT_IDS | `WRK_ECI_ALT_S10_SRC` | Four alternate-id branches |
| 20 | ACTIVE_ALT_IDS | `WRK_ECI_ALT_S20_ACTIVE` | Ids of active parties only |
| 30 | VALIDATED_ROUTED | `WRK_ECI_ALT_S30_ROUTED` | SSN/Medicaid validation + valid / SSN-exception / Medicaid-exception groups |
| 40 | READY_TO_PUBLISH | `WRK_ECI_ALT_S40_READY` | Publish-ready rows with insert-only guards |
| 50 | PUBLISH | — (transaction) | 3 inserts, original order |

Publish targets: `C_S_ECI_PTY_RLE_ALT_ID`, `EXC_STG_BAD_REC_MEMB`
(SSN, then Medicaid).

Preserved quirks: the id written is the source value (standardised
values are validation-only); the SSN exception row has NULL `RUN_DATE`
and the looked-up exception code (NULL when unconfigured), so an
invalid SSN is logged only once, ever (reproduced via the
`uq_ssn_exc` guard); `VERSION_SEQ` = 1; `PERIOD_START_DATE` = source
`DATE_CREATED`.

## 7. m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`

Loads phones and e-mails of the ECI parties. Original parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 5 work tables below |
| 10 | SRC_PHN_EADDR | `WRK_ECI_PHN_S10_SRC` | Phone/e-mail source rows with party, role and record keys |
| 20 | ACTIVE_PHN_EADDR | `WRK_ECI_PHN_S20_ACTIVE` | Rows of active parties only |
| 30 | DQ_CLEAN_VALIDATE | `WRK_ECI_PHN_S30_DQ` | Cleaned phones (7-digit numbers get '000' prefixed), validated e-mails |
| 40 | ROUTED_GROUPS | `WRK_ECI_PHN_S40_ROUTED` | Area-code lookup, phone exception codes, good/bad phone and e-mail groups |
| 50 | READY_TO_PUBLISH | `WRK_ECI_PHN_S50_READY` | Publish-ready rows with insert-only guards |
| 60 | PUBLISH | — (transaction) | 4 inserts, original order |

Publish targets: `C_S_ECI_PTY_RLE_PHN`, `EXC_STG_BAD_REC_MEMB`
(bad phones), `C_S_ECI_PTY_RLE_EADDR`, `EXC_STG_BAD_REC_MEMB`
(bad e-mails).

Preserved quirks: a `Missing_AreaCode` phone is both loaded AND logged;
an e-mail whose `Invalid_Email` code is unconfigured is treated as
valid and loaded (router tests the looked-up code); the phone exception
`SRC_SYS_ID_1` is NULL and its type is the literal 'Bad Value';
`VERSION_SEQ` = '1'; e-mail `PERIOD_REFERENCE_TIME` is NULL.

Framework note: step 40 uses `fn_snow_helper44_common` (area-code
reference) exactly as the original does. That helper's body references
`RDM.REF_PHN_AREA_CD` in the supplied common file, so the install must
make that reference resolve (e.g. a COMMON-qualified reference, as was
noted for the TRS install) — this rewrite does not change the helper
call or invent a replacement.

## 8. m_Tgt_C_S_ECI_Pty_Addr — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr`

Validates addresses and loads the good ones. Original parameters:
`P_MEMBER_HIERARCHY_CODE` ('Member'), `P_MEMBER_HM_REL_TP_CD`
('Member Addr').

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 5 work tables below |
| 10 | SRC_ADDRESSES | `WRK_ECI_ADR_S10_SRC` | Address source rows, party/role keys, translated address type |
| 20 | KEYED_ACTIVE | `WRK_ECI_ADR_S20_KEYED` | Record keys, active addresses only |
| 30 | ADDR_VALIDATION | `WRK_ECI_ADR_S30_VALIDATED` | Address validation result (pass-through stand-in) + state lookup |
| 40 | FLAT_VALIDATION | `WRK_ECI_ADR_S40_FLAT` | Validation result unpacked + match-code description |
| 50 | SCORED_READY | `WRK_ECI_ADR_S50_READY` | Score, issue description, held lines, insert-only guards |
| 60 | PUBLISH | — (transaction) | 3 inserts, original order |

Publish targets: `DQM_ADDRESS` (every active address, first),
`C_S_ECI_PTY_RLE_ADDR` (score '100'), `EXC_STG_BAD_REC_MEMB`
(score '40').

Preserved quirks: the validator is the pass-through stand-in, so every
address with a known type scores '100'; exception rows use the
hard-coded description 'Invalid Address per Address Doctor' and type
'Bad Value' (no catalogue lookup); unfed ports are NULL (including
`FLR_NUM`, `EFF_END_DT`, exception `PERIOD_END_DATE`);
`PERIOD_REFERENCE_TIME` is NULL; `VERSION_SEQ` = 1;
`PERIOD_START_DATE` / `EFF_STRT_DT` = source `LAST_UPDATE_DATE`.

## 9. m_Tgt_C_S_ECI_Pty_Rle_Rel — `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel`

Loads family-to-child relationships in both directions. Original
parameters: none.

| Step | Name | Work table | What it holds |
|---|---|---|---|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_BOTH_DIRECTIONS | `WRK_ECI_REL_S10_SRC` | Family rows doubled (one per direction) |
| 20 | KEYED_BOTH_ACTIVE | `WRK_ECI_REL_S20_KEYED` | Child/family party keys, both parties active |
| 30 | CODED_TRANSLATED | `WRK_ECI_REL_S30_TYPED` | Relationship code built and translated (NULL when untranslated) |
| 40 | READY_TO_PUBLISH | `WRK_ECI_REL_S40_READY` | Relationship keys, exception details, insert-only guards |
| 50 | PUBLISH | — (transaction) | 2 inserts, original order |

Publish targets: `C_S_ECI_PTY_RLE_REL` (translated codes),
`EXC_STG_BAD_REC_MEMB` (untranslated codes).

Preserved quirks: the code translation is a direct `LOOKUP_CODE_VALUE`
lookup (REL_TP / INVERSE_REL, source ECI), not a helper, as in the
original; the exception code is the catalogue-lookup result (NULL when
`Invalid_Relationship` is unconfigured); exception `SRC_SYS_ID_3` ends
in '|' (master code NULL); `VERSION_SEQ` = 1; `PERIOD_START_DATE` =
family `DATE_CREATED`; `CREATE_DATE` = `DATE_MODIFIED`.

## Work-table inventory (all TRANSIENT, all in ECI_ETL_WRK)

- Validation: `WRK_ECI_VAL_S10_SRC`, `WRK_ECI_VAL_S20_ENRICHED`, `WRK_ECI_VAL_S30_ROUTED`
- Pty: `WRK_ECI_PTY_S10_SRC`, `WRK_ECI_PTY_S20_ACTIVE`, `WRK_ECI_PTY_S30_DQ`, `WRK_ECI_PTY_S40_DQ2`, `WRK_ECI_PTY_S50_READY`
- Reactivation Addr: `WRK_ECI_RFA_S10_LATEST`, `WRK_ECI_RFA_S20_KEEPNEW`
- Reactivation Phn: `WRK_ECI_RFP_S10_LATEST`, `WRK_ECI_RFP_S20_KEEPNEW`
- Reactivation Medicaid: `WRK_ECI_RFM_S10_LATEST`, `WRK_ECI_RFM_S20_KEEPNEW`
- Alt_Id: `WRK_ECI_ALT_S10_SRC`, `WRK_ECI_ALT_S20_ACTIVE`, `WRK_ECI_ALT_S30_ROUTED`, `WRK_ECI_ALT_S40_READY`
- Phn_And_EAddr: `WRK_ECI_PHN_S10_SRC`, `WRK_ECI_PHN_S20_ACTIVE`, `WRK_ECI_PHN_S30_DQ`, `WRK_ECI_PHN_S40_ROUTED`, `WRK_ECI_PHN_S50_READY`
- Addr: `WRK_ECI_ADR_S10_SRC`, `WRK_ECI_ADR_S20_KEYED`, `WRK_ECI_ADR_S30_VALIDATED`, `WRK_ECI_ADR_S40_FLAT`, `WRK_ECI_ADR_S50_READY`
- Rel: `WRK_ECI_REL_S10_SRC`, `WRK_ECI_REL_S20_KEYED`, `WRK_ECI_REL_S30_TYPED`, `WRK_ECI_REL_S40_READY`

Total: 32 work tables (3 + 5 + 2 + 2 + 2 + 4 + 5 + 5 + 4). No work table
is shared between mappings; each mapping's step 5 drops only its own
tables (verified: 32 step-5 drops = 32 work tables created).

---
## WIC

# STEP MAP — WIC (wf_WIC_Stage_Load, modular rewrite, simplified v2 style)

Install location: database `MDM_ETL_WIC`, schema `WIC_ETL_WRK`. All table
and procedure names in the rewritten code are unqualified, exactly as in
the originals.

Run order (identical to the original run script
`run_wf_WIC_Stage_Load.sql`, and to the runner
`sp_etl_run_wf_WIC_Stage_Load`):

1. `m_Tgt_C_S_WIC_Pty_Validation`
2. `m_Tgt_C_S_WIC_Pty`
3. `m_Tgt_C_S_WIC_Pty_Addr`
4. `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`
5. `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`

Every mapping starts with step 5 `CLEANUP_PREVIOUS_RUN` (bare
`DROP TABLE IF EXISTS` statements for that mapping's work tables only, no
checkpoint call for drops), then runs every staged step from scratch, then
publishes in a single transaction. Work tables are TRANSIENT, are left
standing after the run, and are cleaned at the start of the next run.
Restart is mapping-level only: there is no step-level resume, no
`P_RESUME_STEP`, and no cleanup procedure. Every mapping appends
`P_JOB_RUN_ID VARCHAR DEFAULT NULL` after its original parameters, in
the same order as the original.

Publish checkpoint row counts are the final work-table row counts feeding
the publish (each branch inserts only its own WHEN-filtered subset), except
where noted. Step checkpoints carry the work-table row count for that step.

---

## 1. m_Tgt_C_S_WIC_Pty_Validation
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation(P_JOB_RUN_ID)`
Original: no parameters; the rewrite appends `P_JOB_RUN_ID` only.

What it does, in plain words: checks the WIC parties and maintains the
deactivation list every later WIC mapping reads. A party whose
standardised first or last name is blank is logged as an exception,
written to the deactivation log, and given a new deactivation-status row
if it has none yet. A party that already has a status and now has both
names present is written to the deactivation log as a reactivation.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below, no checkpoint |
| 10 | ENRICHED | `WRK_WIC_VAL_S10_ENRICHED` | Source parties joined to the current deactivation status (latest row per source key) and the cross-reference hub state, with standardised names computed. The status / cross-reference lookups stay inline here because they are reference lookups, not data stages. Only step that reads `V_WIC_ETL_SRC`. |
| 20 | NAMED_BLANK_TEST | `WRK_WIC_VAL_S20_NAMED` | Standardised first / middle / last names pulled out; the blank-name test applied (`name_missing`). |
| 30 | ROUTED | `WRK_WIC_VAL_S30_ROUTED` | Exception code / attribute name / value, new deactivation status from hub state, looked-up exception description and type, run constants, and the first-row-per-exception-key flag (`uq_exc_name`). Computed before publish, so routing sees the pre-run status. |
| 40 | PUBLISH (one transaction) | — (reads step 30) | See publish targets below. |

Publish targets (step 40, in original INSERT ALL branch order):
- `EXC_STG_BAD_REC_MEMB` — invalid party names (`name_missing AND uq_exc_name`)
- `STG_WIC_PTY_INACTIVE_LOG` — deactivations (`name_missing`)
- `STG_WIC_PTY_INACTIVE_STS` — new deactivation-status rows (`name_missing AND deactivation_sts IS NULL`)
- `STG_WIC_PTY_INACTIVE_LOG` — reactivations (`deactivation_sts IS NOT NULL AND NOT name_missing`)

Preserved quirks: insert-only (the IDQ delete of
`STG_WIC_PTY_INACTIVE_STS` is not performed); the cross-reference lookup
filters on `TRIM(ROWID_SYSTEM) = 'WIC'`; no timeline handling in this
mapping.

---

## 2. m_Tgt_C_S_WIC_Pty
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty(P_PTY_BO_CLASS_CD_MEMBER DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER DEFAULT 'Member', P_JOB_RUN_ID)`
Original parameters, in order: `P_PTY_BO_CLASS_CD_MEMBER`,
`P_RLE_BO_CLASS_CD_MEMBER`; `P_JOB_RUN_ID` appended.

What it does, in plain words: loads the active WIC parties into the party
and party-role tables and logs demographic exceptions. Every active party
loads — an exception never rejects the party, it is loaded AND logged.
Gender, ethnicity and race exceptions are logged only for
`SOURCE_TABLE = 'CLIENT'`; birth date and language exceptions are logged
for every row.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below, no checkpoint |
| 10 | ACTIVE | `WRK_WIC_PTY_S10_ACTIVE` | Active source parties only (parties with a deactivation status removed). Only step that reads `V_WIC_ETL_SRC`. |
| 20 | DQ_STANDARDISE_VALIDATE | `WRK_WIC_PTY_S20_DQ` | Name standardisation, gender, birth date, ethnicity, race indicators, language. |
| 30 | DQ2_EXCEPTION_DETAIL | `WRK_WIC_PTY_S30_DQ2` | Standardised values pulled out; every exception description and type resolved from the exception lookup; birth-date value used downstream is NULL when the birth date raised an exception. |
| 40 | ROUTED | `WRK_WIC_PTY_S40_ROUTED` | Party / role keys, exception routing groups, run constants, birth weight in grams, and the insert-only guards (`uq_pty`, `uq_rle`, `uq_gender`, `uq_birth`, `uq_ethnicity`, `uq_race`, `uq_language`). Guards evaluated here, before publish, as in the original single query. |
| 50 | PUBLISH (one transaction) | — (reads step 40) | See publish targets below. |

Publish targets (step 50, in original INSERT ALL branch order):
- `C_S_WIC_PTY` — valid parties (`uq_pty`)
- `C_S_WIC_PTY_RLE` — valid roles (`uq_rle`)
- `EXC_STG_BAD_REC_MEMB` — invalid gender (`grp_gender AND uq_gender`)
- `EXC_STG_BAD_REC_MEMB` — invalid birth date (`grp_birth AND uq_birth`)
- `EXC_STG_BAD_REC_MEMB` — invalid ethnicity (`grp_ethnicity AND uq_ethnicity`)
- `EXC_STG_BAD_REC_MEMB` — invalid race (`grp_race AND uq_race`)
- `EXC_STG_BAD_REC_MEMB` — invalid language (`grp_language AND uq_language`)

Preserved quirks: insert-only (IDQ truncates of `C_S_WIC_PTY` /
`C_S_WIC_PTY_RLE` not performed); party birth date is the source DOB while
the language exception row writes the mapplet's birth date (NULL for a
future one); birth weight in grams is `BIRTH_WT_OZ * 28.35` (ounces only);
`VERSION_SEQ` hard-coded to 1, `PERIOD_START_DATE = DATEKEY`;
`HUB_STATE_IND` hard-coded to 1.

---

## 3. m_Tgt_C_S_WIC_Pty_Addr
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr(P_MEMBER_HIERARCHY_CODE DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD DEFAULT 'Member Addr', P_JOB_RUN_ID)`
Original parameters, in order: `P_MEMBER_HIERARCHY_CODE`,
`P_MEMBER_HM_REL_TP_CD`; `P_JOB_RUN_ID` appended.

What it does, in plain words: validates the WIC addresses and loads the
good ones into the party-role address table. Every active address is
written to the address-quality table first. A good address (score '100')
loads; an exception address (score '40') is only logged, never loaded.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below, no checkpoint |
| 10 | ACTIVE | `WRK_WIC_ADDR_S10_ACTIVE` | Active source addresses only (deactivation-status filter) + the address key. Only step that reads `V_WIC_ETL_SRC`. |
| 20 | VALIDATED | `WRK_WIC_ADDR_S20_VALIDATED` | Address validation with state 'TX', country 'US', zip only; state code resolved from the state lookup. |
| 30 | FLAT | `WRK_WIC_ADDR_S30_FLAT` | Validation result pulled out into flat columns; match-code description resolved. |
| 40 | SCORED | `WRK_WIC_ADDR_S40_SCORED` | Score ('100' / '40'), exception detail, held address lines, run constants, and the insert-only guards (`uq_addr`, `uq_addr_exc`). Target guard evaluated here, before publish, as in the original single query. |
| 50 | PUBLISH (one transaction) | — (reads step 40) | See publish targets below. |

Publish targets (step 50, in original INSERT ALL branch order):
- `DQM_ADDRESS` — every active address (unconditional branch)
- `C_S_WIC_PTY_RLE_ADDR` — good addresses (`score = '100' AND uq_addr`)
- `EXC_STG_BAD_REC_MEMB` — exception addresses (`score = '40' AND uq_addr_exc`)

Preserved quirks: insert-only (IDQ truncate of `C_S_WIC_PTY_RLE_ADDR`
not performed); address type is the constant '002', so with the
pass-through validator every address scores '100'; exception addresses
are logged only ('Invalid Address per Address Doctor', 'Bad Value');
unfed ports written as NULL (including `SRC_STATE`, even though 'TX'
goes to the validator); `DQM_ADDRESS.PTY_SRC_KEY` is `LPAD(ID, 10, '0')`
(the ECI-only 'F' suffix never applies); `VERSION_SEQ = 1`,
`PERIOD_START_DATE / EFF_STRT_DT = DATE_ADDRESS_VALID_FROM`,
`EFF_END_DT` and `PERIOD_REFERENCE_TIME` NULL.

---

## 4. m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr(P_JOB_RUN_ID)`
Original: no parameters; the rewrite appends `P_JOB_RUN_ID` only.

What it does, in plain words: each active WIC row gives one phone and
possibly one e-mail. Good phones load, bad phones are logged. Non-null
e-mails are validated the same way: valid e-mails load, bad e-mails are
logged.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below, no checkpoint |
| 10 | SRC | `WRK_WIC_PHN_S10_SRC` | Active source rows only (deactivation-status filter) + party-role / phone / e-mail keys, standardised phone, e-mail validation object (NULL when e-mail is null). Only step that reads `V_WIC_ETL_SRC`. |
| 20 | CHECKED | `WRK_WIC_PHN_S20_CHECKED` | Phone exception code from the area-code lookup (usage '001'); standardised e-mail pulled out. |
| 30 | ROUTED | `WRK_WIC_PHN_S30_ROUTED` | Phone / e-mail exception descriptions, codes and types resolved; good / bad routing groups for phones and e-mails. |
| 40 | READY | `WRK_WIC_PHN_S40_READY` | Run constants (phone type 'Telephone', usage '001', preference 'Primary', e-mail type '001', status 'Active', valid 'Y') and the insert-only guards (`uq_phn`, `uq_eaddr`, `uq_phone_exc`, `uq_email_exc`). Target guards evaluated here, before publish, as in the original single query. |
| 50 | PUBLISH (one transaction) | — (reads step 40) | See publish targets below. |

Publish targets (step 50, in original INSERT ALL branch order):
- `C_S_WIC_PTY_RLE_PHN` — good phones (`grp_phone_good AND uq_phn`)
- `EXC_STG_BAD_REC_MEMB` — bad phones (`grp_phone_bad AND uq_phone_exc`)
- `C_S_WIC_PTY_RLE_EADDR` — valid e-mails (`grp_email_good AND uq_eaddr`)
- `EXC_STG_BAD_REC_MEMB` — bad e-mails (`grp_email_bad AND uq_email_exc`)

Preserved quirks: insert-only (IDQ truncates of the phone / e-mail
targets not performed); no null-phone filter — a party without a phone
is validated and logged as an invalid phone; the e-mail key uses the
e-mail as read (no trim); the phone routing groups overlap by
construction — a 'Missing_AreaCode' code counts as both good and bad, so
the original INSERT ALL would write such a row to both the phone table
and the exception table, and the publish INSERTs below keep the same
WHEN conditions (the original header notes 'Missing_AreaCode' only
exists for ECI, so WIC never gets it in practice); `VERSION_SEQ` is '1'
on both targets, `PERIOD_START_DATE = DATEKEY`.

---

## 5. m_Tgt_C_S_WIC_Pty_Rle_Alt_Id
File: `mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id(P_JOB_RUN_ID)`
Original: no parameters; the rewrite appends `P_JOB_RUN_ID` only.

What it does, in plain words: writes one alternate id per active WIC
party — the WIC id padded to 12, type '020' for `SOURCE_TABLE`
'CLIENT' and '021' otherwise. Parties with a deactivation status are
excluded; keys already in the target are skipped.

**Split flag:** this original has no CTE chain — it is a single query
(an inner derived table plus an outer SELECT). The split used is the
closest sensible one: step 10 builds the keys (the original inner
derived table) and step 20 applies the deactivation filter, the
already-loaded guard and the one-row-per-key rank (the original outer
SELECT). Nothing was merged into a single step, and no business
expression was changed.

| Step | Name | Work table | What happens |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below, no checkpoint |
| 10 | KEYS | `WRK_WIC_ALT_S10_KEYS` | Party-role key, id type ('020' / '021'), alternate-id key. Only step that reads `V_WIC_ETL_SRC`. |
| 20 | READY | `WRK_WIC_ALT_S20_READY` | Deactivation filter applied, keys already in the target skipped, one row per alternate-id key (latest `DATEKEY` wins). Guard evaluated here, before publish, as in the original single query. |
| 30 | PUBLISH (one transaction) | — (reads step 20) | See publish target below. |

Publish target (step 30, single INSERT):
- `C_S_WIC_PTY_RLE_ALT_ID` — one alternate id per active party (all rows in step 20; filters and guard already applied there, so the publish count equals the ready-row count)

Preserved quirks: insert-only (IDQ truncate of
`C_S_WIC_PTY_RLE_ALT_ID` not performed); `HUB_STATE_IND` is not linked
(left to the column default); `VERSION_SEQ = 1`,
`PERIOD_START_DATE = DATEKEY`; no validation rule runs in this mapping.

---

## Runner
File: `runners/sp_etl_run_wf_WIC_Stage_Load.sql`
Procedure: `sp_etl_run_wf_WIC_Stage_Load(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Generates a `WIC_WF_` run id when none is passed, writes a
WORKFLOW-level `job_begin` row, calls the 5 mappings in the original run
order passing each mapping's original defaults in full followed by the
run id, then `job_finish`; on failure `job_fail` + `RAISE`. It writes to
no target and drops no work table.

File: `runners/run_wf_WIC_Stage_Load.sql`
SnowSQL script with `!set exit_on_error=true` and a single
`CALL sp_etl_run_wf_WIC_Stage_Load();` (replaces the original script's
5 CALL lines; the scheduler's IDQ command task is still left to the
scheduler).

## Work-table inventory (all TRANSIENT, all in WIC_ETL_WRK)
- Validation: `WRK_WIC_VAL_S10_ENRICHED`, `WRK_WIC_VAL_S20_NAMED`, `WRK_WIC_VAL_S30_ROUTED`
- Party: `WRK_WIC_PTY_S10_ACTIVE`, `WRK_WIC_PTY_S20_DQ`, `WRK_WIC_PTY_S30_DQ2`, `WRK_WIC_PTY_S40_ROUTED`
- Address: `WRK_WIC_ADDR_S10_ACTIVE`, `WRK_WIC_ADDR_S20_VALIDATED`, `WRK_WIC_ADDR_S30_FLAT`, `WRK_WIC_ADDR_S40_SCORED`
- Phone/E-mail: `WRK_WIC_PHN_S10_SRC`, `WRK_WIC_PHN_S20_CHECKED`, `WRK_WIC_PHN_S30_ROUTED`, `WRK_WIC_PHN_S40_READY`
- Alt Id: `WRK_WIC_ALT_S10_KEYS`, `WRK_WIC_ALT_S20_READY`

Total: 17 work tables across 5 mappings. No work table is shared between
mappings; each mapping's step 5 drops only its own tables.

---
## TTF

# STEP MAP — wf_TTF_Stage_Load (TTF, simplified v2 style)

Workflow run order (same as the original run script): Pty_Validation,
Pty, Pty_Rle_Alt_Id, Pty_Rle_Phn. All procedures install in schema
`TTF_ETL_WRK` in database `MDM_ETL_TTF`; all table names are
unqualified in code. Every mapping starts with step 5
`CLEANUP_PREVIOUS_RUN` (bare `DROP TABLE IF EXISTS` for that mapping's
work tables only, no checkpoint for drops), ends with a `TERMINATING`
row, and leaves its work tables standing. Restart is mapping-level
only: a new run. Publish is the only transaction in each mapping.

## 1. m_Tgt_C_S_TTF_Pty_Validation

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Original: no parameters; `P_JOB_RUN_ID` appended.

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | ENRICHED | `WRK_TTF_VAL_S1_ENRICHED` | Clients + latest inactive status + cross-reference row + standardised-name object |
| 20 | NAMED | `WRK_TTF_VAL_S2_NAMED` | Standardised names pulled out + blank / DECLINED / DO_NOT_DISCLOSE flags |
| 30 | ROUTED | `WRK_TTF_VAL_S3_ROUTED` | Router groups (invalid name / deactivation / reactivation) + exception code, description, type + first-row-per-key flag `uq_exc_name` |
| 40 | PUBLISH | — (targets only) | One transaction, 4 inserts (see below) |

Publish targets (step 40, in order):
- `EXC_STG_BAD_REC_MEMB` — invalid party names (`grp_invalid_party_name AND uq_exc_name`)
- `STG_TTF_PTY_INACTIVE_LOG` — deactivation log rows (`grp_deactivation`)
- `STG_TTF_PTY_INACTIVE_STS` — new status rows (`grp_deactivation AND deactivation_sts IS NULL`)
- `STG_TTF_PTY_INACTIVE_LOG` — reactivation log rows (`grp_reactivation`)

Preserved quirks: insert-only (IDQ DD_DELETE of the inactive-status
table not performed); a DO_NOT_DISCLOSE name is logged but does not
deactivate; the source WHERE fragment (test client ids) is not applied;
cross-reference filter is `TRIM(ROWID_SYSTEM) = 'TTF'`.

## 2. m_Tgt_C_S_TTF_Pty

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty(P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member', P_JOB_RUN_ID VARCHAR DEFAULT NULL)`

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | ACTIVE | `WRK_TTF_PTY_S1_ACTIVE` | Active clients only (inactive parties filtered out) + gender decoded from SEXID + ethnicity flag |
| 20 | DQ | `WRK_TTF_PTY_S2_DQ` | Name-standardisation object, gender object, birth-date exception code, ethnicity / race master codes |
| 30 | DQ2 | `WRK_TTF_PTY_S3_DQ2` | Standardised fields + exception descriptions / types pulled out; future birth date nulled |
| 40 | ROUTED | `WRK_TTF_PTY_S4_ROUTED` | Party / role keys, exception groups, constants, insert-only guards `uq_pty / uq_rle / uq_gender / uq_birth / uq_ethnicity / uq_race` |
| 50 | PUBLISH | — (targets only) | One transaction, 6 inserts (see below) |

Publish targets (step 50, in order):
- `C_S_TTF_PTY` — valid parties (`uq_pty`)
- `C_S_TTF_PTY_RLE` — valid roles (`uq_rle`)
- `EXC_STG_BAD_REC_MEMB` — invalid gender (`grp_gender AND uq_gender`)
- `EXC_STG_BAD_REC_MEMB` — invalid birth date (`grp_birth AND uq_birth`)
- `EXC_STG_BAD_REC_MEMB` — invalid ethnicity (`grp_ethnicity AND uq_ethnicity`)
- `EXC_STG_BAD_REC_MEMB` — invalid race (`grp_race AND uq_race`)

Preserved quirks: insert-only (IDQ truncate of party / role targets not
performed); Invalid_Language / Invalid_Suffix groups never write (unfed
ports, no branches generated); PRFRD_LANG_CD and SFX_NM are NULL (unfed
ports); VERSION_SEQ = 1; party PERIOD_START_DATE = run start, role
PERIOD_START_DATE = SUBMITDATE; an exception never stops the party
loading.

## 3. m_Tgt_C_S_TTF_Pty_Rle_Alt_Id

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Original: no parameters; `P_JOB_RUN_ID` appended.

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | KEYS | `WRK_TTF_ALT_S1_KEYS` | Candidate keys for active clients only (party key, submit date, alternate-id key) |
| 20 | DEDUP | `WRK_TTF_ALT_S2_DEDUP` | Keys not already loaded + one row per key (latest submit date wins) |
| 30 | PUBLISH | — (targets only) | One transaction, 1 insert (see below) |

Publish target (step 30):
- `C_S_TTF_PTY_RLE_ALT_ID` — one alternate id per active client, type '024'

FLAGGED — THIN SPLIT: the original is a single short query, not a CTE
chain, so the split above is the closest sensible one. Step 20 is not a
separate business stage in the original; it is the already-loaded guard
+ one-row-per-key dedup half of the one original SELECT, pulled out so
the publish input can be counted and inspected before it lands.

Preserved quirks: insert-only (IDQ truncate not performed); the source
WHERE fragment (test client ids) is not applied; VERSION_SEQ = 1;
PERIOD_START_DATE = run start.

## 4. m_Tgt_C_S_TTF_Pty_Rle_Phn

File: `mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
Original: no parameters; `P_JOB_RUN_ID` appended.

| Step | Name | Work table | What it does |
|------|------|-----------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | SRC | `WRK_TTF_PHN_S1_SRC` | Non-NULL phones of active clients only + phone key + standardised phone |
| 20 | CHECKED | `WRK_TTF_PHN_S2_CHECKED` | Phone validation code (area-code lookup included); NULL = good phone |
| 30 | ROUTED | `WRK_TTF_PHN_S3_ROUTED` | Exception description, constants, insert-only guards `uq_phn / uq_phone_exc` |
| 40 | PUBLISH | — (targets only) | One transaction, 2 inserts (see below) |

Publish targets (step 40, in order):
- `C_S_TTF_PTY_RLE_PHN` — good phones (`phone_exception_code IS NULL AND uq_phn`)
- `EXC_STG_BAD_REC_MEMB` — bad phones as 'Rejected Record' exceptions (`phone_exception_code IS NOT NULL AND uq_phone_exc`)

Preserved quirks: insert-only (IDQ truncate not performed);
Bad_Phone_Ext records never occur (unfed extension port, no branch
generated); exception SRC_SYS_ID_2 is NULL (unfed ID_PHONE port); the
source invalid SQL fragment is not applied; VERSION_SEQ = '1';
PERIOD_START_DATE = SUBMITDATE; a bad phone is logged only, never
loaded.

## Runner

- `runners/sp_etl_run_wf_TTF_Stage_Load.sql` —
  `sp_etl_run_wf_TTF_Stage_Load(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`.
  Generates `TTF_WF_...` when NULL, writes a WORKFLOW-level job_begin
  row, calls the 4 mappings in the original run-script order passing
  each mapping's original defaults in full followed by the run id, then
  job_finish; on failure, job_fail + RAISE. Writes to no target and
  drops no work table itself.
- `runners/run_wf_TTF_Stage_Load.sql` — SnowSQL script: header comment,
  `!set exit_on_error=true`, a single `CALL sp_etl_run_wf_TTF_Stage_Load();`.

---
## FSS

# Step map — wf_FSS_Stage_Load (FSS, modular rewrite)

Install schema is `FSS_ETL_WRK` in database `MDM_ETL_FSS`. All table
names in the procedures are unqualified, as in the originals.

Run order (same as the original `run_wf_FSS_Stage_Load.sql`):

1. `m_Tgt_C_S_FSS_Pty_Validation`
2. `m_Tgt_C_S_FSS_Pty`
3. `m_Tgt_C_S_FSS_Pty_Addr`
4. `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`
5. `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`
6. `m_Tgt_C_S_FSS_Pty_Rle_Rel`

Every mapping starts with step 5 `CLEANUP_PREVIOUS_RUN`: bare
`DROP TABLE IF EXISTS` statements for that mapping's work tables only,
with no checkpoint call for the drops. Every mapping ends with step 50
`PUBLISH` (the only transaction) and a terminating row; work tables
are left standing after the run. There is no step-level restart and no
resume parameter — a restart is simply a new run.

## 1. m_Tgt_C_S_FSS_Pty_Validation

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 3 work tables below |
| 10 | SRC | `WRK_FSS_VAL_S1_SRC` | Source clients: last active registration or all-inactive rows |
| 20 | ENRICHED | `WRK_FSS_VAL_S2_ENRICHED` | Standardised names + blank-name flag, current deactivation status, cross-reference state |
| 30 | ROUTED | `WRK_FSS_VAL_S3_ROUTED` | Invalid-name / deactivation / reactivation groups, exception details, first-row-per-exception-key flag |
| 50 | PUBLISH | — | 4 INSERTs in one transaction |

Publish targets: `EXC_STG_BAD_REC_MEMB` (invalid names),
`STG_FSS_PTY_INACTIVE_LOG` (deactivations),
`STG_FSS_PTY_INACTIVE_STS` (new deactivation statuses, reactivation
statuses).

## 2. m_Tgt_C_S_FSS_Pty

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty(P_PTY_BO_CLASS_CD_MEMBER DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER DEFAULT 'Member', P_JOB_RUN_ID)`
Original parameters in order: `P_PTY_BO_CLASS_CD_MEMBER`,
`P_RLE_BO_CLASS_CD_MEMBER`; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_PTY_S1_SRC` | Source clients, deactivated parties removed |
| 20 | DQ_CHECKS | `WRK_FSS_PTY_S2_DQ` | Name standardisation, gender, birth date, ethnicity, race, language, suffix checks |
| 30 | DQ2_EXCEPTIONS | `WRK_FSS_PTY_S3_DQ2` | Standardised values with exception codes / descriptions / types resolved |
| 40 | ROUTED | `WRK_FSS_PTY_S4_ROUTED` | Party / role keys, exception groups, insert-only guards |
| 50 | PUBLISH | — | 8 INSERTs in one transaction |

Publish targets: `C_S_FSS_PTY`, `C_S_FSS_PTY_RLE`,
`EXC_STG_BAD_REC_MEMB` (gender, birth-date, ethnicity, race, language,
suffix exceptions).

## 3. m_Tgt_C_S_FSS_Pty_Addr

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr(P_MEMBER_HIERARCHY_CODE DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD DEFAULT 'Member Addr', P_JOB_RUN_ID)`
Original parameters in order: `P_MEMBER_HIERARCHY_CODE`,
`P_MEMBER_HM_REL_TP_CD`; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_ADDR_S1_SRC` | Source addresses with address key built, deactivated parties removed |
| 20 | VALIDATED | `WRK_FSS_ADDR_S2_VALIDATED` | Address validation result attached, state code translated |
| 30 | FLAT | `WRK_FSS_ADDR_S3_FLAT` | Validation result flattened into plain columns, match-code description resolved |
| 40 | SCORED | `WRK_FSS_ADDR_S4_SCORED` | Good / exception score, held address lines, exception details, insert-only guards |
| 50 | PUBLISH | — | 3 INSERTs in one transaction |

Publish targets: `DQM_ADDRESS` (every active address),
`C_S_FSS_PTY_RLE_ADDR` (good addresses),
`EXC_STG_BAD_REC_MEMB` (exception addresses).

## 4. m_Tgt_C_S_FSS_Pty_Rle_Alt_Id

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 2 work tables below |
| 10 | SRC_KEYED | `WRK_FSS_ALT_S1_SRC` | Keyed source rows: role key, alternate-ID type ('022' / '023') and key, last active registrations |
| 20 | FILTERED | `WRK_FSS_ALT_S2_FILTERED` | Deactivated parties and existing keys removed, first row per key kept |
| 50 | PUBLISH | — | 1 INSERT in one transaction |

Publish target: `C_S_FSS_PTY_RLE_ALT_ID`.

Flagged split note: this mapping has no CTE chain in the original —
its whole logic is one keyed query plus filters — so it stages into
just two work tables before publish. That is the closest sensible
split; nothing was merged into a single step to hide it. Publish keeps
step number 50 for consistency with the other mappings.

## 5. m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_PHN_S1_SRC` | Source rows with role, e-mail and phone keys built, deactivated parties removed |
| 20 | DQ_VALIDATE | `WRK_FSS_PHN_S2_DQ` | E-mail validation, phone standardisation, extension check |
| 30 | CHECKED | `WRK_FSS_PHN_S3_CHECKED` | Standardised e-mail, phone exception code (area-code lookup), standardised extension + its exception code |
| 40 | ROUTED | `WRK_FSS_PHN_S4_ROUTED` | Exception details, good / bad groups for e-mail, phone and extension, insert-only guards |
| 50 | PUBLISH | — | 5 INSERTs in one transaction |

Publish targets: `C_S_FSS_PTY_RLE_EADDR` (valid e-mails),
`C_S_FSS_PTY_RLE_PHN` (valid phones),
`EXC_STG_BAD_REC_MEMB` (bad e-mails, bad phones, bad extensions).

## 6. m_Tgt_C_S_FSS_Pty_Rle_Rel

File: `mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql`
Procedure: `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel(P_JOB_RUN_ID)`
Original parameters: none; `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended.

| Step | Name | Work table | What it does |
|------|------|------------|--------------|
| 5 | CLEANUP_PREVIOUS_RUN | — (drops only) | Drops the 4 work tables below |
| 10 | SRC_ACTIVE | `WRK_FSS_REL_S1_SRC` | Source relationships, both parties off the deactivation list |
| 20 | CODED | `WRK_FSS_REL_S2_CODED` | Relationship code built (missing code defaults to CAREGIVER), direction code type, output gender, both role keys |
| 30 | TYPED | `WRK_FSS_REL_S3_TYPED` | Relationship code translated through the code-value lookup |
| 40 | FINAL | `WRK_FSS_REL_S4_FINAL` | Relationship key, constants, exception details, insert-only guards |
| 50 | PUBLISH | — | 2 INSERTs in one transaction |

Publish targets: `C_S_FSS_PTY_RLE_REL` (valid relationships),
`EXC_STG_BAD_REC_MEMB` (untranslated relationships).

## Runner

- `runners/sp_etl_run_wf_FSS_Stage_Load.sql` —
  `sp_etl_run_wf_FSS_Stage_Load(P_JOB_RUN_ID VARCHAR DEFAULT NULL)`:
  workflow-level `job_begin`, the 6 mappings in the order above with
  each mapping's original defaults in full followed by the run id,
  then `job_finish`; on failure `job_fail` + `RAISE`. It writes no
  target rows and drops no work tables itself.
- `runners/run_wf_FSS_Stage_Load.sql` — SnowSQL script with
  `!set exit_on_error=true` and a single `CALL` to the runner.

---
## CRE

# STEP_MAP_CRE — CRE mappings (shared multi-source framework)

Source of truth: the step numbers, step names, work tables and publish targets below are copied
from the procedure header and checkpoint calls in `mappings/` (the simplified-v2 CRE rewrite).
Business logic is unchanged; the only adaptation is the shared-framework control calls
(see Notes). Step names are the checkpoint `P_STEP_NAME` values, verbatim.

## Notes (apply to every mapping below)

- **Control calls:** every control call passes SOURCE first: `sp_etl_job_begin('CRE', …)`,
  `sp_etl_checkpoint('CRE', …)`, `sp_etl_job_finish('CRE', …)`, `sp_etl_job_fail('CRE', …)`
  (via a `c_source VARCHAR DEFAULT 'CRE'` variable in each procedure). Job-run-id prefixes are
  `CRE_` for mappings, `CRE_WF_` for workflow runners.
- **Control table:** the shared job-control table with a SOURCE column (framework-owned),
  not a CRE-only table.
- **Install schema:** all table names are unqualified. Install in schema `CRE_ETL_WRK` in
  database `MDM_ETL_CRE`, so unqualified names resolve to that schema's tables.
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
- **Split note (this mapping):** the suggested boundaries were adapted to where the original CTEs
  actually compute things, and the adaptation is flagged here rather than hidden. The US address
  validation call itself (`fn_snow_helper34_common`) runs in step 30 (original `dq2`), while the
  US-vs-abroad split (`addr_valid` plus all `a_*` address fields) is computed in step 40 (original
  `flat`), because `addr_valid` is derived from that validation result. Likewise the phone and
  alternate-id validation results (`phone_std`, `ci`, `md`, `sn`) are computed in step 30 (original
  `dq`/`dq2`), while the alternate-id keys, values and exception resolution are built in step 40
  (original `flat`). No business expression was changed by this placement; each step's SELECT is the
  original CTEs, with FROM clauses pointed at the previous work table.
- **Preserved quirks worth naming (from the procedure header, unchanged from the original):**
  `CRE_SRC_MRG` also gets moves whose CARE ids have no cross-reference (NULL records), and the move
  target row again when it carries a `MAINT_FLAG`; the CARE ID alternate id of an unmerged move is
  the target id; the state and alternate-id type lookups have no code-type filter, so an untranslated
  type leaves `ALT_ID_TP` and the exception's `SRC_SYS` NULL; the phone and address exception rows
  have no unique-key guard; `member_rle_fk` hard-codes `'Member'` while `rle_key` uses the
  `P_RLE_BO_CLASS_CD_MEMBER` parameter.

## Workflow: wf_CRE_Stage_Load_Ongoing

Runner: `runners/sp_etl_run_wf_CRE_Stage_Load_Ongoing.sql` (run script: `runners/run_wf_CRE_Stage_Load_Ongoing.sql`, single runner CALL).

### 1. m_Tgt_C_S_CRE_CARE_Clients

- Procedure file: `mappings/sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql`
- Workflow: `wf_CRE_Stage_Load_Ongoing`
- Original parameters (in order, before the appended `P_JOB_RUN_ID`):
  `P_PHYSICAL_ADDR_TYPE_CD` = `'002'`, `P_RLE_BO_CLASS_CD_MEMBER` = `'Member'`,
  `P_DEFAULT_TX_STATE_CD` = `'48'`, `P_COUNTY_CD_NONTX` = `'996'`,
  `P_COUNTYCD_DEFAULTALL` = `'998'`, `P_DEFAULT_NONUS_STATE_CD` = `'99'`
- Steps (step 5 cleanup precedes all of these; see Notes):
  - Step 10: `SRC_MERGE_ROUTING` — CARE snapshot (new/changed, deleted, moved, move targets) + merge routing from the party cross-reference and merge history (original CTEs: `src`, `xref`, `hmrg_src`, `hmrg_tgt`, `routed`)
  - Step 20: `NAME_STANDARDISE_VALIDATE` — name standardisation + valid-member flag + end-dated flag (original CTEs: `named`, `members`)
  - Step 30: `RANK_ENRICH` — rank per CARE id (record type descending) + gender, ethnicity, race, phone, CARE/Medicaid/SSN validation and US address validation (original CTEs: `ranked`, `dq`, `dq2`)
  - Step 40: `FLAT_ADDR_ALTID` — flattened load-ready rows: US vs abroad address split, phone key, alternate-id keys/values, exception codes, timeline dates (original CTEs: `alt_tp`, `flat`)
  - Step 50: `KEYED_ROUTES_GUARDS` — county rule, address/phone/alternate-id keys, route flags, run constants, SRC_ROWIDs cut to 30 characters, insert-only unique-key guards (original CTEs: `keyed` + final select)
  - Step 60: `PUBLISH` — publish transaction (18 INSERTs, one per original INSERT ALL branch, in original order)
- Work tables (all `CREATE OR REPLACE TRANSIENT TABLE`):
  - `WRK_CRE_CARE_S1_SRC_MRG`
  - `WRK_CRE_CARE_S2_NAMED`
  - `WRK_CRE_CARE_S3_RANKED`
  - `WRK_CRE_CARE_S4_FLAT`
  - `WRK_CRE_CARE_S5_KEYED`
- Publish targets:
  - `CRE_SRC_MRG`
  - `C_S_CRE_PTY`
  - `C_S_CRE_PTY_RLE`
  - `C_S_CRE_PTY_RLE_ADDR`
  - `C_S_CRE_PTY_RLE_PHN`
  - `C_S_CRE_PTY_RLE_ALT_ID`
  - `EXC_STG_BAD_REC_MEMB`

