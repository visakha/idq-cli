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
