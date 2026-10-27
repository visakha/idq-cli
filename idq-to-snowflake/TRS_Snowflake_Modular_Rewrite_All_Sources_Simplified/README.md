# Snowflake Modular ETL Rewrite — All Sources (Simplified style)

One zip, six sources, one style: **TRS, ECI, WIC, TTF, FSS, CRE**.
Every procedure in this package is a modular rewrite of a supplied
original Snowflake procedure: the same business SQL, split from one
giant single-block statement into staged steps that write to named
TRANSIENT work tables, with a checkpoint row after every step. This is
the **simplified v2 style** approved for the TRS rewrite
(`TRS_Snowflake_Modular_Rewrite_Simplified_v2.zip`): mapping-level
restart only, no step-level resume, no checkpoint for work-table drops.

The TRS procedures here are adapted from that v2 package with logic
unchanged (only the control calls gained a `SOURCE` argument). The
previous TRS zips are untouched. Nothing in this package was invented:
every mapping comes from an original supplied for its source, and
every shared helper comes from the supplied common files, unchanged.

## Layout

```
README.md                              -- this file
STEP_MAP_ALL_SOURCES.md                -- combined step map (all 6 sources)
00_framework/
  01_job_control_ddl.sql               -- JOB_CONTROL_ETL + 5 views (shared)
  02_job_control_procs.sql             -- sp_etl_job_begin / sp_etl_checkpoint /
                                          sp_etl_job_finish / sp_etl_job_fail (shared)
  common/
    01_snow_common_functions.sql       -- fn_snow_helperNN_common, unchanged
    02_snow_common_lookups.sql         -- helper lookups, unchanged
TRS/  ECI/  WIC/  TTF/  FSS/  CRE/      -- one folder per source
  mappings/                            -- rewritten sp_snow_main_* procedures
  runners/                             -- sp_etl_run_<workflow> + run_<workflow>.sql
  STEP_MAP_<SRC>.md                    -- per-source step map
```

Per-source contents (40 mapping procedures, 7 workflow runners):

| Source | Workflows | Mappings | Runner(s) |
|---|---|---|---|
| TRS | wf_TRS_Stage_Load_1_Ongoing, wf_TRS_Stage_Load_TOA | 15 (14 + 1) | sp_etl_run_wf_TRS_Stage_Load_1_Ongoing, sp_etl_run_wf_TRS_Stage_Load_TOA |
| ECI | wf_ECI_Stage_Load | 9 | sp_etl_run_wf_ECI_Stage_Load |
| WIC | wf_WIC_Stage_Load | 5 | sp_etl_run_wf_WIC_Stage_Load |
| TTF | wf_TTF_Stage_Load | 4 | sp_etl_run_wf_TTF_Stage_Load |
| FSS | wf_FSS_Stage_Load | 6 | sp_etl_run_wf_FSS_Stage_Load |
| CRE | wf_CRE_Stage_Load_Ongoing | 1 | sp_etl_run_wf_CRE_Stage_Load_Ongoing |

Note: six sources yield **seven** workflows (and seven run scripts)
because TRS has two stage-load workflows. TRS mappings are flattened
into a single `TRS/mappings/` directory; the two TRS runners keep the
workflows apart.

## Install order

1. **Shared framework first** — in database `MDM_ETL_COMMON`, schema
   `COMMON`:
   - `00_framework/01_job_control_ddl.sql` (table `JOB_CONTROL_ETL`,
     views `VW_ETL_JOB_CURRENT`, `VW_ETL_JOB_STEPS`,
     `VW_ETL_OPEN_WORK_TABLES`, `VW_ETL_RUNS_NEEDING_ATTENTION`,
     `VW_ETL_JOB_STORY`)
   - `00_framework/02_job_control_procs.sql`
   - `00_framework/common/01_snow_common_functions.sql`
   - `00_framework/common/02_snow_common_lookups.sql`
2. **Then one source at a time** (repeat per source):
   ```
   USE DATABASE MDM_ETL_<SRC>;   -- e.g. MDM_ETL_ECI
   USE SCHEMA <SRC>_ETL_WRK;      -- e.g. ECI_ETL_WRK
   ```
   Install `<SRC>/mappings/*.sql`, then `<SRC>/runners/sp_etl_run_*.sql`.
   All procedure and table names are unqualified, exactly as in the
   originals, so they resolve into the schema above.
3. **Run** with SnowSQL, e.g. `snowsql -c <connection> -f
   <SRC>/runners/run_<workflow>.sql`. Each run script contains a
   single CALL to its workflow runner, with `!set exit_on_error=true`.
   The IDQ command task (`touch <workflow>.ind`) is still left to the
   scheduler, as in the originals.

## The style rules (identical in every procedure)

- **Same name, same parameters, one appended.** Each procedure keeps
  its original name and its original parameters in the original order,
  with `P_JOB_RUN_ID VARCHAR DEFAULT NULL` appended. Every existing
  CALL still works; a runner passes the run id last.
- **Staged steps in tens** (10, 20, 30, …). The original CTE/logic
  chain is split at natural boundaries into `CREATE OR REPLACE
  TRANSIENT TABLE WRK_<SRC>_<short>_<step>_<name>` steps. No cursors,
  no session TEMP tables. Each step writes a checkpoint row
  (`WORKING` / `CREATED`, row count, business purpose).
- **Step 5 `CLEANUP_PREVIOUS_RUN` at the start.** Bare `DROP TABLE IF
  EXISTS` statements for that mapping's work tables only. **No
  checkpoint is recorded for these drops** — there are zero `DROPPED`
  checkpoint calls anywhere in this package (the simplified v2 change).
  `DROPPED` remains only as a retained `WORK_TABLE_ACTION` value in
  the framework.
- **Publish is the only transaction.** One INSERT per original
  `INSERT ALL` branch, inside one `BEGIN TRANSACTION … COMMIT`, then
  a checkpoint outside the transaction, then the `TERMINATING` row.
  Work tables are **left standing** after the run.
- **Mapping-level restart only.** No `P_RESUME_STEP`, no resume
  guards, no end-of-run drops, no cleanup procedure. A restart is
  simply a new run (new `JOB_RUN_ID`); each mapping cleans up the
  previous run's work tables at its step 5 and runs every step fresh.
  Runners are sequential calls passing only `P_JOB_RUN_ID`; they never
  write to targets or drop work tables.
- **Business SQL preserved, not fixed.** Same expressions, filters,
  unique-key guards (`uq_*`), insert-only behaviour. Quirks visible
  in the originals are noted in procedure headers as PRESERVED (see
  "Flagged gaps and preserved quirks" below), never silently fixed.
- **Job control is shared.** One table, `JOB_CONTROL_ETL`, with a
  `SOURCE` column (`TRS | ECI | WIC | TTF | FSS | CRE`). Every
  control call takes the source first:
  `sp_etl_job_begin(<SRC>, workflow, mapping, run_id)`,
  `sp_etl_checkpoint(<SRC>, run_id, workflow, mapping, state, step,
  name, status, …)`, `sp_etl_job_finish(<SRC>, …)`,
  `sp_etl_job_fail(<SRC>, …)`. Run ids are prefixed per source
  (`TRS_`, `ECI_`, …; runners `TRS_WF_`, `ECI_WF_`, …), so one
  workflow run's whole history is readable with one filter.
  (Minor form note: most files pass the source as a `:c_source`
  variable; the ECI files pass the literal `'ECI'`. Same runtime
  value, both valid against the framework signature.)
- **Checkpoint arity.** Step and publish checkpoints pass 16
  arguments (the trailing error-message argument is left to its
  default); `EXCEPTION`-block checkpoints pass all 17, including the
  error message. Both match the framework signature.

## How to read a run afterwards

- `VW_ETL_JOB_STORY WHERE SOURCE = '<SRC>' AND JOB_RUN_ID = '…' ORDER
  BY EVENT_ID` — the whole run as a story.
- `VW_ETL_JOB_CURRENT` — where each run is right now.
- `VW_ETL_OPEN_WORK_TABLES` — which work tables are still standing.
- `VW_ETL_RUNS_NEEDING_ATTENTION` — failed or interrupted runs (a run
  with no `TERMINATING` row was interrupted).

## Flagged gaps and preserved quirks

Read the per-source `STEP_MAP_<SRC>.md` and the procedure headers for
the full lists. The items that matter most:

1. **Not compiled against a live Snowflake, no row-count parity run
   yet — for any source.** That is a required pre-production step,
   as it was for the TRS rewrite. Two constructs are worth confirming
   at compile time: `QUALIFY` carried verbatim into a CTAS step (ECI
   Medicaid step 20, WIC Alt_Id step 20) and `SQLROWCOUNT`
   accumulation across publish INSERTs.
2. **`fn_snow_helper44_common` (phone area codes) internally
   references `RDM.REF_PHN_AREA_CD` in the supplied common file.**
   The install must make that reference resolve (e.g. a
   COMMON-qualified reference or synonym) — same note as for the TRS
   install. No helper was invented; all 34 helpers referenced across
   the 40 mappings resolve to definitions in the included common
   files (11 supplied helpers are simply never referenced).
3. **Insert-only everywhere, as in the originals.** No TRUNCATE or
   DELETE was added, including IDQ deletes/truncates the originals
   note as not performed. A re-run therefore inserts nothing twice
   (unique-key guards) but does not remove rows an IDQ truncate
   would have removed.
4. **TRS (adapted from v2, logic unchanged):** party deactivation
   step 50 `DELETE_VALID_STAGE_NOT_PERFORMED` is checkpoint-only and
   writes no data — the valid-member spine delete is not performed
   (see the production decisions sheet, item D1). Auth_Rep does not
   delete its own attribute type first (D2). `PROCESSED_YN` is left
   to column default in relationship deactivation capture (D3).
5. **ECI:** the three reactivation mappings are single-INSERT
   originals with no CTE chain; each is split as latest-rows →
   keep-new filter → publish (the keep-new filter still sees the
   pre-run delta table, as in the original). Preserved Medicaid
   reactivation defect: with the default `P_TEST_LOOKUP_RESULT='N'`
   the filter tests the source `ID_MEDICAID` (never NULL), so the
   mapping writes no rows — exactly as IDQ does; `'Y'` tests the
   lookup result instead. Pty exception rows carry the literal
   `m_Tgt_C_S_ECI_Pty_OnGoing`, not the mapping's name.
6. **FSS:** Validation reactivation writes to the status table
   (`STG_FSS_PTY_INACTIVE_STS`), not the log, as ported in the
   original — so a reactivated client stays excluded by later
   mappings' non-null-status filter. Flagged for business
   confirmation. NULL capture action / inactive flag is not treated
   as "not deleted / not inactive", so such rows are not reactivated.
7. **WIC:** Phn_And_EAddr keeps the good/bad phone-group overlap for
   `Missing_AreaCode` verbatim (the original header notes WIC never
   gets that code in practice). Alt_Id `HUB_STATE_IND` is left to
   column default.
8. **TTF / WIC / FSS Alt_Id thin splits (flagged, not hidden):**
   those originals are single short queries with no CTE chain, so
   each is split into candidate keys → ready/dedup → publish rather
   than merged into one step.
9. **CRE:** the single procedure's 13-CTE chain is split into 5
   staged steps + publish (18 INSERT branches, in original order).
   Preserved quirks include: `CRE_SRC_MRG` also gets moves with no
   cross-reference (NULL records) and the move-target row again when
   it carries `MAINT_FLAG`; untranslated state/alt-id-type lookups
   leave `ALT_ID_TP` and the exception's `SRC_SYS` NULL; the
   pass-through address validator means every US address is an
   exception; `'B'`/`'D'` end-dating as in the original.
10. **Scope notes.** No BR numbers or IDQ-comparison claims were
    invented for the non-TRS sources; their headers describe steps in
    plain business words only. The four deactivation workflows
    (Initial / Relationship / History / Complete) are **not** in
    this package — same scope as the TRS v2 rewrite; this package
    covers the stage-load workflows only.

## Verification performed on this package (before zipping)

- 40 rewritten mapping procedures, names matching the 40 originals
  exactly (TRS 15, ECI 9, FSS 6, WIC 5, TTF 4, CRE 1).
- All 7 workflow runners call their mappings in exactly the original
  run-script order, with original defaults passed in full.
- Zero `DROPPED` checkpoint arguments, zero `P_RESUME_STEP`, zero
  TEMP tables, zero non-TRANSIENT table creations, zero cursor code
  (the word CURSOR appears only in header prose stating one was not
  used), exactly one transaction per mapping, `P_JOB_RUN_ID` in
  every procedure file.
- 152 TRANSIENT work tables; every mapping's step-5 drop set equals
  its create set exactly; no work table is shared across mappings.
- Every referenced helper resolves to the included common files.
- TRS outputs diffed against the v2 package: only the `SOURCE`
  argument, the `c_source` declaration, and the
  `JOB_CONTROL_ETL_TRS` → `JOB_CONTROL_ETL` comment renames differ.
- Previous TRS zips untouched.
