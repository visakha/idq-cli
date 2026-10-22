# Gathered knowledge, to-dos and improvements (002)

Parking note written on **2026-10-21**, at `main` = `e988b29` (PR #20). It follows
[gathered-kb-todos-and-improvements-001.md](gathered-kb-todos-and-improvements-001.md) (written at `028b9a2`, PR #17)
and records only **what changed since then**, **what is newly open** and **what moved** on the 001 lists. Anything
not mentioned here still stands as written in 001.

Findings about how the IDQ mappings behave remain in [docs/common_insights.md](docs/common_insights.md).

**Contents**

1. [Where we left off](#1-where-we-left-off)
2. [Status of the 001 to-dos](#2-status-of-the-001-to-dos)
3. [New open to-dos, by priority](#3-new-open-to-dos-by-priority)
4. [New decisions needed from the business](#4-new-decisions-needed-from-the-business)
5. [Process improvements](#5-process-improvements)
6. [Code and tooling improvements](#6-code-and-tooling-improvements)
7. [Knowledge map: what moved](#7-knowledge-map-what-moved)
8. [Ground rules, updated](#8-ground-rules-updated)
9. [Suggested restart checklist](#9-suggested-restart-checklist)

---

## 1. Where we left off

Three PRs since 001:

| PR | What it did |
|---|---|
| #18 | Parking note 001. |
| #19 | `etl_process=ORA_SP`: a third engine next to `JAVA` and `IDQ`. `OraSpRunner` calls the `sp_ors_main_*` procedures of `idq-to-oracle/` over JDBC, in the order of `run_<workflow>.sql`. The first failure stops the run and marks the rest `SKIPPED`. `mock_ora_sp=true` (default) only reports the `EXEC` calls. |
| #20 | **`compare-etl-process`** and an **insert-only code base** (details below). |

**`compare-etl-process`** (CLI command; also `POST /api/etl/compare/{source}`)

- Prompts for a source system (numbered list; Enter keeps the latched one) or takes `ECI` / `2` as an argument.
- No mock data. Runs ORA_SP, then IDQ through the `infacmd` script (which polls until the workflow ends).
- Snapshots the tables with `SELECT *` before, between and after the runs. The ORA_SP result is the rows that run
  added; the IDQ result is the rows added after that. If Informatica emptied a target itself (its own *Truncate
  target table* setting), the whole table counts as the IDQ result and the report notes it.
- Compares on every column except `idq.compare.ignore-columns`. Rows with the same `PKEY_SRC_OBJECT` are paired and
  the differing columns listed.
- Report: `compare_runs_<SOURCE>/<SOURCE>_ORA_SP_vs_IDQ_<time>.md`, including a check that every source table is
  unchanged after each run.
- Code: `workflow/EtlCompareRunner`, `config/CompareSettings`; `WorkflowRunner.run(source, engine)` runs any engine
  regardless of `etl_process`.

**Insert-only code base.** The CLI may now be run against production, so nothing deletes, truncates or drops in
Oracle any more:

| Area | Before | Now |
|---|---|---|
| Java target loads | `ReplaceAll` / `ReplaceWhere` / `DeleteByKey`, guarded by `clearable-tables.txt` | `LoadMode.Append` only; repositories expose no delete; whitelist removed |
| Inactive status (ECI, FSS, TTF, WIC validation) | reactivation deleted the `STG_<SRC>_PTY_INACTIVE_STS` row | reactivation is only logged |
| TRS mapping 002 (auth. rep.) | pre-SQL `DELETE ... WHERE MNG_ATTR_TP = ...` | appends |
| Mock fills | `deleteRange` / `deleteMarked` / raw `DELETE`, then insert | `MockTables.skipIfPresent` / `skipIfMarked` / `skipIf`: existing mock rows are kept and the table is not filled again |
| `idq-to-oracle` procedures | `sp_ors_helper01_common` (TRUNCATE) in ~40 places, 5 `DELETE` statements | removed; each place marked `-- Not performed: ...` |

Unit tests: **47, all passing** (`mvnw test`). The ECI and FSS validation PKEY tests were changed to expect no
status-row removal.

## 2. Status of the 001 to-dos

| 001 item | Status |
|---|---|
| P1 *Compare outputs with IDQ* | **Tooling exists** (`compare-etl-process`), **never run** against real IDQ. Still open. |
| P1 *Compile `idq-to-oracle/`* | Still open, and more urgent: the procedures changed in #20 (see N1). |
| P1 `OracleWorkflowIT` for TRS/FSS/TTF/WIC, `SourceEntitiesIT`, PowerCenter import | Unchanged, open. |
| P2 coverage gaps (5 deactivation mappings in Java, PC for 4 sources, `fn_dq_*`, address validation, real sample data, reference data, external objects) | Unchanged, open. |
| P3 *remove `tables.deleteRange(...)`* ([code_cleanup_001.md](code_cleanup_001.md)) | **Done** in #20. Replaced by `skipIfPresent`, which never deletes; clean-up of mock rows is left to the user, as asked. |
| P3 tutoring note on `SampleData.fillMockAll` | Still open. Note that its behaviour changed: mock rows are now generated once and reused. |
| P3 `idq-to-cdi` folder name in `ext-tools/README.md` and `idq-to-pc/wf_ECI_Stage_Load/README.md` | Still open (3 occurrences). |
| P3 `STG_REF_PHN_AREA_CD_TEST` leftover table | Still open (DBA task; this repo will not drop it). |
| P3 delete remote branches of merged PRs | Still open, and the list grew: 20 remote branches besides `main`, including `etl-process-ORA_SP`, `etl-process-compare`, `parking-notes-001`. |
| Process 2 *three-way regression harness* | Partly done: ORA_SP vs IDQ is automated; Java is not part of the comparison yet (see N6). |

## 3. New open to-dos, by priority

### P1: before anything touches production

- [ ] **N1. Reinstall the procedures.** Any schema where `idq-to-oracle/install.sql` ran before #20 still has the old
      `sp_ors_main_*` that **truncate and delete**, and the old `sp_ors_helper01_common`. Re-run `install.sql`, then
      drop the old helper **by hand, as a DBA** (this repo will not do it). Until then, `etl_process=ORA_SP` is not
      insert-only in that schema.
- [ ] **N2. First real run of `compare-etl-process`**, with `-Dmock_ora_sp=false -Dmock_infacmd=false`, on one
      source (ECI is the best tested). Known runtime risks to check first:
      - Spring Shell 4: the prompt relies on `@Argument(defaultValue = "")` plus an injected `CommandContext`. If the
        prompt does not appear, start there.
      - `infacmd` script: `docs/batch-script-windows.original.bat` hard-codes its own workflow name and credentials
        and ignores the workflow argument `IdqCommandRunner` passes. It must be parameterised before it can run a
        real workflow.
- [ ] **N3. Decide how targets are emptied before a load** (see D11). Without truncate, a second load of the same
      source rows duplicates the `C_S_*` rows or fails with `ORA-00001`. This also affects `compare-etl-process`:
      both engines insert into the same targets, one after the other, so a unique key makes the second one fail.

### P2: correctness gaps opened by insert-only

- [ ] **N4. Reactivation no longer clears the inactive status** (ECI, FSS, TTF, WIC; Java and Oracle). Reactivated
      parties stay filtered out by every later mapping. Needs D12.
- [ ] **N5. `STG_TRS_VALID_MEMBERS` keeps deactivated members** (`sp_ors_main_m_Tgt_C_S_TRS_Pty_Deactivation_1`).
      The Java port does not have this mapping, so only ORA_SP is affected. Needs D12.
- [ ] **N6. Add the Java engine to the comparison** (`compare-etl-process` takes two engines today). A generic
      `compare <engineA> <engineB>` would cover Java vs IDQ and Java vs ORA_SP too.

### P3: clean-up

- [ ] **N7.** About 28 `*Service` classes still take `EtlSettings` in their constructor but no longer use it (it was
      only needed for the whitelist). Remove it together with the PKEY tests' constructor calls.
- [ ] **N8.** `docs/common_insights.md` does not yet mention that the ports deliberately skip IDQ's truncate and
      `DD_DELETE` (§6 *IDQ engine semantics* and §12 *Risks when re-platforming* are the natural places).

## 4. New decisions needed from the business

Numbering continues from 001 (D1–D10).

| # | Question | Options |
|---|---|---|
| D11 | **Who empties the `C_S_*` targets before a load**, now that the application never truncates? | (a) A DBA job or the MDM stage process empties them; (b) a separate, explicitly approved maintenance script outside this repo; (c) make the targets run-scoped (e.g. load only new keys). |
| D12 | **Reactivation and deactivation without deletes.** IDQ removes the status row on reactivation and the member from `STG_TRS_VALID_MEMBERS` on deactivation. | (a) Accept the drift and handle it outside; (b) replace the delete with an "end-date" or flag column update, if the tables can take one; (c) let the readers ignore statuses older than the latest *Reactivation* log row. |
| D13 | Is `compare-etl-process` meant for production, or only for a test schema with production-like data? | It is read-only itself, but it runs both real engines, which write the targets twice. |

D1 (FSS writes *Reactivation* into the status table) interacts with D12: with no delete, the FSS status table now
keeps both the old status and the *Reactivation* row.

## 5. Process improvements

1. **Safety rule as a check, not a habit.** Add a unit test (or a build step) that fails when `DELETE`, `TRUNCATE` or
   `DROP` appears in `src/main`, `src/main/resources` or `idq-to-oracle/*.sql` outside comments. The scan used in #20
   was a one-off `grep`.
2. **Record the engine and version with each comparison.** Keep the `compare_runs_*` reports with the
   `EXC_LOOKUP_CODE_VALUE` snapshot (001 process item 4), so a difference can be traced to configuration.
3. **Separate "can it run" from "is it right".** For each engine, first a smoke run on a few rows (N2), then the
   comparison. #19 and #20 were both written without a live database.
4. **Keep the parking notes numbered and incremental** (this file updates 001, it does not repeat it).

## 6. Code and tooling improvements

**`compare-etl-process`**

- Tables are held in memory in full (`SELECT *`), including the `C_B_*` and lookup tables the mappings read.
  For large schemas, fingerprint the source tables in Oracle (`COUNT(*)` plus `ORA_HASH` per row) instead of
  reading them.
- "Rows added" is a multiset difference over all columns. It cannot tell a re-inserted identical row from an
  existing one. A run id or `CREATE_DATE >= run start` filter per table would be exact.
- `idq.compare.ignore-columns` is global; some tables may need their own list.
- When `mock_ora_sp` or `mock_infacmd` is true the command still runs and only warns. Consider refusing instead.

**Java**

- N6 (generic engine comparison) and N7 (unused `EtlSettings`).
- `IdqCommandRunner` waits on the script's output stream with no timeout. A hung `infacmd` blocks the shell.

**Oracle (`idq-to-oracle/`)**

- Compile (001 P1), then N1.
- The validation procedures still compute the reactivation keys (log rows with `ACTION_DT = l_run_ts`) that fed the
  removed `DELETE`; that code is harmless but could be simplified once D12 is decided.

**ext-tools**

- `idmc_spec.py` generates the *Oracle stored procedure* sections from the procedure headers. Regenerate `docs-from-idq-exports/`:
  28 places there still say "truncated first", but the headers were reworded in #20.

## 7. Knowledge map: what moved

| Need | Look in |
|---|---|
| ORA_SP vs IDQ comparison: how to run it, what the report means | [user-guide-cli.md §15](user-guide-cli.md#15-task-compare-ora_sp-with-idq) |
| Safety rules (insert-only) | [user-guide-cli.md §1](user-guide-cli.md#1-concepts-in-five-minutes), [idq-to-oracle/README.md](idq-to-oracle/README.md) (*Insert only* note) |
| ORA_SP engine | [user-guide-cli.md §7](user-guide-cli.md#7-task-run-the-etl-workflow), `workflow/OraSpRunner.java` |
| Comparison reports | `compare_runs_<SOURCE>/` |
| ~~Tables a mapping may empty~~ | **Removed**: `db/clearable-tables.txt` no longer exists |
| Mock fill without deletes | `mock/MockTables.java` (`skipIfPresent`, `skipIfMarked`, `skipIf`, `exists`) |

## 8. Ground rules, updated

001's rules still apply, with one replaced and one added:

- ~~*Never drop tables from the app. A full delete only happens for tables listed in `clearable-tables.txt`.*~~
- **Insert only, everywhere.** No `DELETE`, `TRUNCATE` or `DROP` in the Java code, the tests, or any SQL the Java
  code runs (including the `idq-to-oracle` procedures). The only DDL is `CREATE TABLE` from
  `db/missing-objects.sql`. When an IDQ step deletes or truncates, leave it out and mark it `-- Not performed: ...`.
- **Mock rows are generated once.** Re-running a fill keeps them. Clean-up is manual, by the user.

## 9. Suggested restart checklist

1. `git switch main && git pull`, then read this file, then 001 §2–§3 for the older open items.
2. `mvnw test` (47 tests, no database needed).
3. If the work touches ORA_SP: N1 first (reinstall the procedures, DBA drops the old helper).
4. If the work touches IDQ: parameterise the `infacmd` script (N2), then a first `compare-etl-process` on ECI.
5. Chase answers for D11–D13 (and D1–D10 from 001).
6. New work on its own branch; new findings to `docs/common_insights.md`; new open items to
   `gathered-kb-todos-and-improvements-003.md`.
