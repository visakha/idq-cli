# Test Harness — Design

A redesign from first principles, written as a system thinker and
as a tester. The question it answers is not "how do we move rows
fast" but "how does a tester know, at 9 AM, whether yesterday's
Snowflake build reproduces yesterday's Production IDQ result --
and how does she trust that answer?"

## 1. The system, in one paragraph

Every day by 8 AM, the Production ETL has completed in Oracle
Production. Its inputs (`ETL_INPUT_TABLES`: the `_D_` and `_H_`
tables and other supporting tables) and its outputs
(`ETL_OUTPUT_TABLES`: the `C_S_*` target tables, the
Status/State-tracking tables, the `ZZ_*` tables) are the expected
result. The harness freezes that expected result into a file
(`Prod_SQLite`), loads the same inputs into Dev Oracle, runs the
Snowflake ETL under test in Snowflake Dev, freezes its result into
a second file (`Dev_SQLite`), and compares the two files record by
record into a third file (`Compare_Results_SQLite`) that a human
verifies in a UI. Nothing in the harness is the system under test;
the harness is the instrument that measures it.

## 2. Design principles (and what each one forbids)

1. **The expected result is frozen before the test runs.**
   Prod outputs are copied before Dev runs anything. If Prod and
   Dev shared a live connection, a late Production change mid-test
   would look like a Snowflake defect. Files freeze time.
2. **One source at a time, one run id everywhere.**
   Tables are mostly source-specific, so a run names its source
   and every artifact of that run (control-store row, results DB
   rows, results filename) carries the same run id. A result that
   cannot be traced to the run that produced it is not evidence.
3. **Explicit over inferred, always.**
   Tables, columns, PKs and runner procedures are data in
   `harness/catalog.py`. Nothing is reflected from a database at
   runtime, nothing is built by string concatenation, and no
   request ever supplies a table or procedure name that reaches
   SQL unchecked. If the catalog does not name it, the harness
   refuses it -- loudly, with the name in the error.
4. **No ORM, no mini-ORM, SQLAlchemy Core only.**
   Pydantic models describe API contracts. Dataclasses describe
   internal results. SQLAlchemy `Table` objects, built fresh from
   the catalog on every call, describe database tables. There is
   no session, no declarative model, no automap, no query builder
   that hides SQL, and no "generic repository" that turns a table
   name into a query by convention. A reader can see every
   statement the harness issues by reading `store.py` and
   `compare.py` -- two files, no magic.
5. **Simple, not clever; short, not terse.**
   One class moves rows (`Store`). One function merges rows
   (`compare_tables`). One module owns each safety rule. A
   function that needs a comment to explain its trick has the
   wrong shape; rewrite it until the code is the explanation.
   Verbosity is not simplicity: the whole harness is 14 Python
   files, and the longest is the pipeline service at ~450 lines.
6. **Fail closed, fail loudly, fail before writing.**
   Every safety rule in §6 is checked before the step writes
   anything. A step that cannot prove it is safe does not run
   partially -- it refuses, names the reason, and leaves the
   previous state untouched.
7. **A partial answer is labelled partial, never rounded.**
   Counts are always complete. Stored diff detail is capped, but
   the cap never changes a count. A verdict of PARTIAL means
   "the evidence is incomplete", which is a different claim from
   MISMATCH ("the evidence is complete and it differs") and from
   MATCH. Conflating them is how bad builds ship.

## 3. Architecture

```
Tester ──► FastAPI (harness/api.py) ──► pipeline steps (harness/pipeline.py)
                │                              │
                │ rules only                 │ rules only
                ▼                              ▼
         RunStore (audit)              Store (rows) ──► Oracle Prod (read)
                │                              │         Oracle Dev (write)
                │                              │         Snowflake Dev (CALL)
                │                              ▼
                │                       compare.py ──► Compare_Results_SQLite
                │                              │
                └──────────── results file ◄──┘
                                              │
                                     Streamlit UI (step G, reads the file only)
```

Module map (dependency order; nothing imports sideways):

| Module | Owns | Must never do |
|---|---|---|
| `config.py` | Settings from the environment | Connect to anything |
| `catalog.py` | Tables, columns, PKs, runner allowlist | Import a database driver |
| `store.py` | Row movement between any two engines | Decide which tables to move |
| `whitelist.py` | Step-C safety file | Touch a database |
| `runs.py` | Audit trail (Core table) | Hold ETL data |
| `compare.py` | Merge compare + results schema | Call an API or a procedure |
| `pipeline.py` | Steps A-F, safety gates, run ids | Build SQL (it uses `Store`) |
| `demo.py` | DEMO ONLY data + simulator | Run in real mode |
| `api.py` | HTTP: validate -> service -> record | Touch a database directly |

The Streamlit app is deliberately outside this diagram's write
path: it reads a results file with the standard library. A viewer
that can write to the system under test is not a viewer.

## 4. Daily flow as a state machine

```
  (A) PRECONDITION ── readiness() ──► ready? ── no ──► STOP, report missing tables
      (Production ETL done by 8 AM; confirmed by hand + readiness check)
        │ yes
  (B) PROD ──► Prod_SQLite (fresh file, inputs + outputs, counts verified)
        │
  (C) PROD_SQLite ──► Dev Oracle (whitelist-gated truncate + load, counts verified)
        │
  (D) SNOWFLAKE DEV ──► runners in order; a failure stops later runners
        │
  (E) SNOWFLAKE DEV ──► Dev_SQLite (fresh file, outputs, counts verified)
        │
  (F) PROD_SQLite × Dev_SQLite ──► Compare_Results_SQLite (verdict + diffs)
        │
  (G) HUMAN ──► Streamlit UI reads Compare_Results_SQLite, verifies by hand
```

Invariants the tester checks at each transition:

- After (B): every copied table's SQLite count equals its Prod
  count, or that table is FAILED (the run still reports the
  others -- one bad table must not hide the rest).
- After (C): every loaded Dev table's count equals its
  Prod_SQLite count. Dev tables that do not exist are NOT_FOUND,
  never created by step C (creating Dev schema is a setup job,
  not a test step, or a typo would silently create an empty
  table and "pass" with zero rows on both sides -- the classic
  empty-equals-empty false pass).
- After (D): runners ran in registry order; a failed runner's
  successors report NOT_RUN, never "skipped silently".
- After (E): Dev_SQLite holds exactly what Snowflake Dev holds
  for the requested outputs.
- After (F): the verdict follows §7's rule, mechanically, from
  the table statuses. No human judgement in the verdict; human
  judgement belongs in step G, reading the diffs.

Idempotency: (B) and (E) always write fresh files (timestamp +
random suffix, so back-to-back runs cannot collide or overwrite
each other's evidence). (C) truncates then loads, so it is safe
to re-run. (D) is NOT idempotent by default, because the Snowflake
runners are insert-only with existing-key guards: re-running (D)
without clearing Dev outputs suppresses rows. That is a property
of the system under test, not a harness bug, and the harness
exposes it honestly: `reset_outputs=true` truncates Dev outputs
first, and the demo simulator always resets (it owns its own
outputs). A harness that silently cleared Dev outputs on every
(D) run would hide the re-run behaviour the tester may need to
see.

## 5. What is compared, and what is not

Only `ETL_OUTPUT_TABLES` are compared. Inputs are not compared,
because Dev receives them verbatim from Prod in step C --
comparing them would only re-prove the copy, and copy counts
already prove it. This is a deliberate scope cut, and it is the
reason the compare can be record-by-record instead of
count-by-count: the compared set is the ETL's product, not its
raw material.

The compare itself is a merge on the registered PK, both sides
streamed in PK order:

- same PK, all columns equal -> MATCHED (counted, not stored);
- same PK, a column differs -> DIFFERENT (differing columns and
  both values stored; only differing columns' values, not the
  whole row, so a wide table's diff stays readable);
- PK on one side only -> ONLY_IN_PROD / ONLY_IN_DEV (the full
  row from the side that has it stored, so the tester can see
  what is missing, not just that something is missing).

Cross-engine value normalisation (dates to ISO strings, numbers
to shortest decimal strings, bytes to hex, None stays None) is
the one place the harness "interprets" data, and it is confined
to `compare.normalize()`, tested directly. Its known limit --
exotic floats compare on their shortest string form -- is
documented in the user guide, not buried.

## 6. Safety model (a tester's threat model for her own tool)

The harness is dangerous by design: step C truncates tables, step
D runs procedures, step E reads a Dev install. Its safety rules
are therefore about the harness harming the wrong database, not
about outside attackers (the API key is the only auth, and the
tool is meant to run on the tester's own machine):

| Threat | Rule | Where enforced |
|---|---|---|
| Truncating Production by misconfiguration | Step C refuses when Prod and Dev connections are identical, before anything is written | `pipeline.sqlite_to_dev` |
| Truncating the wrong Dev table | Only whitelist-listed tables are truncated; a non-listed table is a 400 naming every offender, and nothing is truncated; a missing whitelist file fails the step outright | `whitelist.py` + step C |
| Running an arbitrary procedure | Step D accepts workflow keys from the catalog allowlist only; a raw procedure name from a request can never reach SQL | `catalog.py` + step D |
| Reading/writing an arbitrary file | File arguments are bare filenames inside the SQLite directory; separators and `..` are rejected; compare read-back takes the file from the run record, never the request | `pipeline.resolve_file`, `api.get_compare` |
| Silently comparing the wrong data | Unknown table/workflow/source names are 400s; unregistered sources return 400 naming the gap, never empty runs; missing tables are statuses, not omissions | `catalog.tables_for`, compare |
| Losing evidence | Fresh files per run (no overwrite); one run id across control store, results DB and filename; diff counts complete even when stored detail is capped | `pipeline.compare_sqlites` |
| Mistaking a demo for a real run | Demo mode is an explicit switch; demo responses name the simulator; demo files are separate from real URLs | `config.py`, step D |
| Secret leakage | No password, token or key is ever logged or returned; Snowflake auth uses the same SSO/key-pair mechanisms as the ETL itself | `config.py`, `pipeline.build_engines` |

What the harness does NOT protect against, honestly: it cannot
prove the 8 AM Production ETL actually ran (readiness proves
tables exist, not freshness -- confirm by hand); it cannot prove
a Snowflake procedure's body is correct (CREATE-time checks do
not resolve body references; only a CALL does, which is what
step D is for); and it cannot stop a tester who deliberately
whitelists a Production table and points Dev at Production --
the prod==dev guard catches identical connections, not a tester
overriding both URLs to the same database under different names.
That last case is a process failure, and the whitelist file's
header says so in plain language.

## 7. Results file schema (Compare_Results_SQLite)

Three tables, created explicitly in `compare.py`, no ORM:

- `compare_runs(run_id, source, prod_sqlite, dev_sqlite,
  started_at, finished_at, status, verdict, message)` -- one row
  per compare run.
- `table_summary(run_id, table_name, status, prod_count,
  dev_count, matched, different, only_in_prod, only_in_dev,
  diff_rows_stored, message)` -- one row per table. Counts are
  never capped.
- `row_diffs(run_id, table_name, status, pk_json,
  differing_columns_json, prod_values_json, dev_values_json)` --
  one row per DIFFERENT / ONLY_IN_* row, capped per table by
  `DIFF_CAP` (default 10000). When the cap bites,
  `diff_rows_stored < different + only_in_prod + only_in_dev`,
  and the summary still tells the tester the true totals.

Verdict rule (mechanical, from table statuses):
MATCH iff every table is MATCH; MISMATCH iff some table is
MISMATCH and none is incomplete; PARTIAL iff any table is
MISSING_IN_PROD, MISSING_IN_DEV, COUNT_ONLY, or FAILED.
A MISMATCH is a successful compare with a negative answer (HTTP
200), not an error: the tester acts on it directly.

## 8. Tester strategy: how this harness is itself tested

A test harness that is not tested is a second system under test
with no oracle. This one is tested in layers, each layer catching
a different class of lie:

1. **Unit tests for the safety and comparison primitives.**
   Whitelist parsing (comments, blanks, case), filename
   rejection, copy count verification, and the compare engine's
   four statuses plus diff detail, missing-table PARTIAL,
   PK-less COUNT_ONLY, and diff-cap behaviour (counts complete,
   stored detail capped). These tests use SQLite only and run
   in seconds; they are the specification for the failure modes.
2. **Gate tests for the dangerous steps.**
   Step C with a non-whitelisted table must refuse AND leave
   the Dev table untouched (the test asserts the old row is
   still there -- a refusal that truncates anyway is the worst
   bug this harness could have). Step C with identical Prod/Dev
   must refuse. Unknown tables/workflows are 400s.
3. **End-to-end demo test.**
   The full A-F flow in demo mode against SQLite stand-ins,
   asserting the exact expected counts (see the user guide's
   demo table). The demo's planted differences are the oracle:
   if the compare ever reports anything other than the planted
   set, either the harness or the simulator regressed, and the
   test fails either way -- which is the point.
4. **Fault-injection scenarios the tester should add next**
   (documented here, not yet automated): a Dev table missing
   entirely (expect MISSING_IN_DEV + PARTIAL); a duplicate PK on
   one side (the merge counts it twice -- decide whether that is
   a DIFFERENT or a data-quality failure and encode the decision
   in a test); a NULL PK value (sort order of NULLs differs by
   engine -- pin it in `normalize` and test it); a column added
   to Prod but not to the catalog (expect a copy that ignores
   it, visibly, because columns are explicit -- then update the
   catalog and re-run); a run interrupted mid-copy (fresh files
   mean the partial file is simply abandoned, never resumed
   into -- assert no half-file is ever returned as a result).
5. **What is NOT tested here, by design.**
   Live Oracle and live Snowflake behaviour (connection auth,
   procedure CALL semantics, warehouse/role errors) cannot be
   tested without those systems. The demo mode substitutes
   SQLite stand-ins for all three sides, which proves the
   harness logic, not the live drivers. The first live run
   should be treated as a test of the drivers, with the demo's
   expected counts as the reference, and its failures recorded
   as new tests, not as one-off fixes.

## 9. Decisions log (alternatives considered, and why not)

| Decision | Alternative | Why not |
|---|---|---|
| Three SQLite files, not one shared schema | One Snowflake schema with a DATA_SOURCE discriminator (the v5 design) | Files freeze time and travel with the tester; a schema couples the test to a live database and to discriminator discipline in every procedure. The v5 flow still exists for that use; this harness is the file-based alternative, not a replacement. |
| PK merge in Python, not SQL EXCEPT/MINUS | Set operations in SQL | SQL set ops differ by dialect (Oracle MINUS vs Snowflake EXCEPT, NULL handling) and cannot stream diff detail with column names. Python merge is dialect-free and its output is exactly the diff the tester reads. Cost: both sides must sort the same way -- hence the PK requirement. |
| Per-table results, run continues on failure | Fail fast on first bad table | A tester needs the whole picture in one run: five good tables and one bad table is more informative than one bad table and four unknowns. Fail-fast exists only as a validation rule (before writing), never as a copy rule. |
| Whitelist file, not a database table | Whitelist in the control store | A file is reviewable in version control, diffable in a pull request, and readable without running anything. A database whitelist is invisible until queried. |
| No scheduler | Cron inside the harness | Scheduling is an operations concern with its own failure modes (missed runs, overlapping runs, stale data). The harness exposes readiness; the tester (or her scheduler) decides when to run. A cron that copies stale data silently is worse than no cron. |
| Dataclasses + Pydantic, no ORM | SQLModel / Django-style models | The user's standing rule, and the right one here: models that describe API contracts (Pydantic) and plain data (dataclasses) cannot smuggle queries, sessions, or lazy loading into a test tool. |
| Sample registry (10 tables), not the full 50 | Full TRS catalog copied in | A design document's code should be readable in one sitting. The full catalog is a data-expansion job (same pattern, more rows), documented in the user guide, not a design change. Shipping an invented 50-table catalog would be worse than shipping a true 10-table one. |

## 10. Limitations (stated plainly, so they become next work)

- No scheduler (see §9). Step A is a precondition + a check.
- Tables without a registered PK compare by counts only
  (PARTIAL verdict). Registering PKs is the fix, not a smarter
  compare.
- Other sources' tables are not registered (runners only).
- The ZZ table's columns are sample columns, not Oracle DDL.
- Float comparison is shortest-string (see §5).
- Diff detail is capped per table (counts are not).
- Live Oracle/Snowflake drivers are not tested here (see §8.5).
- The API has API-key auth only; run it locally, not on a
  shared server. The Streamlit app has no auth at all, by
  design, for the same reason.
