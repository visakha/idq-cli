# Test Harness — User Guide (v1.0.0)

Read `DESIGN.md` first if you want the reasoning (principles,
safety model, decisions log). This guide is the doing: install,
configure, run the daily flow, run the demo, extend the registry,
and fix what breaks.

## 1. The daily flow

| Step | What happens | Endpoint / tool |
|---|---|---|
| (A) | By 8 AM the Production ETL has completed. Inputs (`_D_`, `_H_`, supporting tables) and outputs (`C_S_*`, Status/State, `ZZ_*`) are ready in Oracle Production. This is a precondition, not a job. Check it with readiness below, and confirm the ETL finished by hand. | `GET /pipeline/readiness` |
| (B) | Copy inputs + outputs from Oracle Production into `Prod_SQLite`. | `POST /pipeline/prod-to-sqlite` |
| (C) | Copy `Prod_SQLite` into Dev Oracle, truncating ONLY tables in `White_list_tables_safe_to_truncate.txt`. | `POST /pipeline/sqlite-to-dev` |
| (D) | Run the Snowflake ETL for a source in Dev. | `POST /pipeline/run-snowflake-etl` |
| (E) | Copy outputs from Snowflake Dev into `Dev_SQLite`. | `POST /pipeline/snowflake-to-sqlite` |
| (F) | Compare `Prod_SQLite` vs `Dev_SQLite` record by record into `Compare_Results_SQLite`. | `POST /pipeline/compare` |
| (G) | Verify by hand in the Streamlit app, reading `Compare_Results_SQLite`. | `streamlit run streamlit_app.py` |

Only outputs are compared. Inputs are verified by copy counts
in (B) and (C); comparing them would only re-prove the copy.

## 2. Install

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill it in (see §3)
uvicorn harness.api:app --port 8000
```

Docs: `http://localhost:8000/docs`. If `API_KEY` is set, every
endpoint except `/health` and `/pipeline/sources` needs the
`X-API-Key` header.

For the Streamlit UI only, on the machine that runs it:

```bash
pip install -r requirements-streamlit.txt
streamlit run streamlit_app.py
```

For development (tests + lint):

```bash
pip install -e ".[dev,ui]"
pytest tests/ -q
ruff check harness scripts streamlit_app.py tests
ruff format --check harness scripts streamlit_app.py tests
mypy harness scripts streamlit_app.py
```

## 3. Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DEMO_MODE` | `false` | `true` = demo mode: all three sides are SQLite files under `DEMO_DIR`. A missing demo file is an error naming the seed script, never a silent empty database. |
| `DEMO_DIR` | `./demo` | Demo database directory. |
| `SQLITE_DIR` | `./pipeline_data` | Directory for `prod_*`, `dev_*`, `compare_*` files. |
| `ORACLE_PROD_URL` | — (required in real mode) | Full SQLAlchemy URL for Oracle Production, e.g. `oracle+oracledb://user:password@host:1521/service`. Production is read-only to this API: it is never written. |
| `ORACLE_DEV_URL` | — (required in real mode) | Full SQLAlchemy URL for Dev Oracle. |
| `WHITELIST_PATH` | `./config/White_list_tables_safe_to_truncate.txt` | Whitelist file for step C. |
| `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, `SNOWFLAKE_AUTHENTICATOR`, `SNOWFLAKE_OAUTH_TOKEN`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_ROLE` | — | Snowflake Dev connection (same SSO/key-pair mechanisms as the ETL itself). |
| `SNOWFLAKE_SOURCE` | `TRS` | Drives `SNOWFLAKE_DATABASE` / `SNOWFLAKE_SCHEMA` defaults (`MDM_ETL_<SOURCE>` / `<SOURCE>_ETL_WRK`) unless set explicitly. |
| `COPY_BATCH_SIZE` | `5000` | Rows per streamed batch. |
| `DIFF_CAP` | `10000` | Stored diff rows per table (counts always complete). |

## 4. Real-use setup checklist

1. **Dev Oracle mirrors Production's schemas.** Step C never
   creates Dev tables: a missing Dev table is NOT_FOUND and the
   run goes PARTIAL. Create Dev tables first (same names and
   Oracle schemas as Production).
2. **Whitelist.** Edit
   `config/White_list_tables_safe_to_truncate.txt` so it lists
   exactly the Dev tables a reload may safely empty, one per
   line. The shipped file lists this design's 10 registry
   tables; extend it as you extend the registry (§8). Never list
   a Production table.
3. **Snowflake Dev install.** Install the source's procedures
   into `SNOWFLAKE_DATABASE.SNOWFLAKE_SCHEMA` before the first
   (D) run.
4. **Re-runs and insert-only runners.** The Snowflake runners are
   insert-only with existing-key guards, so re-running (D)
   without clearing Dev outputs suppresses rows. Either run (D)
   with `"reset_outputs": true` (truncates Dev outputs first)
   or use a fresh schema. Demo mode always resets (the
   simulator truncates its own outputs).
5. **Step (E) copies all rows** from the Snowflake Dev output
   tables (no discriminator filter): in a fresh Dev schema the
   only rows are the ones (D) just wrote. If your Dev schema
   also holds older rows, clear it first (see point 4).

## 5. Endpoint reference

All endpoints are under `/pipeline`. `source` defaults to `TRS`.

- `GET /pipeline/sources` -- registry: sources, runner keys and
  procedures, table names. No API key required.
- `GET /pipeline/readiness?source=TRS` -- step A check: every
  input + output table's existence and row count on the Prod
  side. `ready` is true only when every registered table exists.
  Empty tables do not block readiness (an empty exception table
  is normal). Readiness proves existence, not freshness.
- `POST /pipeline/prod-to-sqlite` -- step B. Body:
  `{"source": "TRS", "tables": [...]}` (`tables` omitted = all
  inputs + outputs). Creates a fresh `prod_TRS_<ts>_<id>.db` and
  returns its filename in `sqlite_path`.
- `POST /pipeline/sqlite-to-dev` -- step C. Body:
  `{"source": "TRS", "prod_sqlite": "prod_TRS_....db",
  "tables": [...]}`. Refuses (400) if Prod and Dev connections
  are identical, or if any requested table is not whitelisted
  (naming every offender, truncating nothing). Truncates each
  whitelisted Dev table, loads it, verifies counts.
- `POST /pipeline/run-snowflake-etl` -- step D. Body:
  `{"source": "TRS", "workflows": ["toa", "ongoing"],
  "reset_outputs": false}`. `workflows` omitted = the source's
  stage-load runners in order (TRS: TOA, then Ongoing). TRS also
  accepts `deactivation-initial`, `deactivation-relationship`,
  `deactivation-history`, `deactivation-complete`. A failure
  stops later workflows (NOT_RUN). In demo mode the response
  names the demo simulator.
- `POST /pipeline/snowflake-to-sqlite` -- step E. Body:
  `{"source": "TRS", "tables": [...], "include_inputs": false}`.
  `tables` omitted = all outputs. Creates a fresh
  `dev_TRS_<ts>_<id>.db`, returned in `sqlite_path`.
- `POST /pipeline/compare` -- step F. Body:
  `{"source": "TRS", "prod_sqlite": "prod_TRS_....db",
  "dev_sqlite": "dev_TRS_....db", "tables": [...]}`. Writes
  `compare_TRS_<ts>_<id>.db` and returns `run_id`, `status`,
  `verdict`, `results_db`, and one summary per table.
  Verdicts: **MATCH** = every table matched exactly;
  **MISMATCH** = at least one table differs (HTTP 200, a
  successful compare with a negative answer); **PARTIAL** =
  evidence incomplete (table missing, PK-less COUNT_ONLY, or
  failed). Per-row statuses: **DIFFERENT** (differing columns
  + both values stored), **ONLY_IN_PROD**, **ONLY_IN_DEV**
  (full row from the side that has it stored).
- `GET /pipeline/compare/{run_id}` -- read results back.
  Query params: `table`, `status` (`DIFFERENT`,
  `ONLY_IN_PROD`, `ONLY_IN_DEV`), `limit` (default 200, max
  5000). The file comes from the run record, never the request.
- `GET /pipeline/compare-runs` -- recent compare runs, newest
  first, with verdicts and results filenames.

Overall step status: COMPLETED (every table ok), PARTIAL (some
ok), FAILED (none ok). A validation failure is a 400 raised
before anything is written.

## 6. Demo walkthrough (no real databases)

Everything below was run against the shipped sample pack and
produces exactly the outputs shown.

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# Demo databases are shipped prebuilt in demo/; rebuild any time with:
python scripts/seed_demo.py
export DEMO_MODE=true DEMO_DIR=./demo SQLITE_DIR=./pipeline_data
export WHITELIST_PATH=./config/White_list_tables_safe_to_truncate.txt
uvicorn harness.api:app --port 8000
```

In a second shell (API key is empty in demo mode):

```bash
TABLES='["STG_TRS_D_DC_INDV","STG_TRS_D_INDV_ADDR","STG_TRS_H_DC_INDV","STG_TRS_D_DC_RELATIONSHIPS","LOOKUP_CODE_VALUE","C_S_TRS_PTY","C_S_TRS_PTY_RLE_PHN","STG_TRS_VALID_MEMBERS","EXC_STG_BAD_REC_MEMB","ZZ_UTL_UNMERGE_TREE_SRC_KEY"]'
OUTS='["C_S_TRS_PTY","C_S_TRS_PTY_RLE_PHN","STG_TRS_VALID_MEMBERS","EXC_STG_BAD_REC_MEMB","ZZ_UTL_UNMERGE_TREE_SRC_KEY"]'

# (A) readiness: the 10 registry tables exist on the Prod side
curl "http://localhost:8000/pipeline/readiness?source=TRS"
# -> ready: true, 10 of 10 tables exist

# (B) Prod -> Prod_SQLite (10/10 copied: inputs 6, 6, 2, 2, 4;
#     outputs 6, 5, 6, 1, 2)
PROD=$(curl -s -X POST http://localhost:8000/pipeline/prod-to-sqlite \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"TRS\",\"tables\":$TABLES}" \
  | python -c "import json,sys; print(json.load(sys.stdin)['sqlite_path'])")

# (C) Prod_SQLite -> Dev
curl -s -X POST http://localhost:8000/pipeline/sqlite-to-dev \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"TRS\",\"prod_sqlite\":\"$PROD\",\"tables\":$TABLES}"
# -> status COMPLETED

# (D) demo simulator run
curl -s -X POST http://localhost:8000/pipeline/run-snowflake-etl \
  -H 'Content-Type: application/json' -d '{"source":"TRS"}'
# -> status COMPLETED, workflow (demo-simulator)

# (E) Snowflake Dev -> Dev_SQLite
DEV=$(curl -s -X POST http://localhost:8000/pipeline/snowflake-to-sqlite \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"TRS\",\"tables\":$OUTS}" \
  | python -c "import json,sys; print(json.load(sys.stdin)['sqlite_path'])")

# (F) compare
curl -s -X POST http://localhost:8000/pipeline/compare \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"TRS\",\"prod_sqlite\":\"$PROD\",\"dev_sqlite\":\"$DEV\",\"tables\":$OUTS}"
```

Expected step (F) result (verdict MISMATCH -- the planted demo
differences, §7):

| Table | Status | Prod | Dev | Matched | Different | Only Prod | Only Dev |
|---|---|---|---|---|---|---|---|
| C_S_TRS_PTY | MISMATCH | 6 | 6 | 4 | 1 | 1 | 1 |
| C_S_TRS_PTY_RLE_PHN | MATCH | 5 | 5 | 5 | 0 | 0 | 0 |
| STG_TRS_VALID_MEMBERS | MATCH | 6 | 6 | 6 | 0 | 0 | 0 |
| EXC_STG_BAD_REC_MEMB | MISMATCH | 1 | 2 | 1 | 0 | 0 | 1 |
| ZZ_UTL_UNMERGE_TREE_SRC_KEY | MATCH | 2 | 2 | 2 | 0 | 0 | 0 |

Then step (G):

```bash
pip install -r requirements-streamlit.txt
streamlit run streamlit_app.py
```

The app offers the newest `compare_*.db` in `./pipeline_data`.
Pick the run, then `C_S_TRS_PTY`: one DIFFERENT row (member
1003, `LST_NM`/`FULL_NM` White -> Changed), one ONLY_IN_PROD
row (1005) and one ONLY_IN_DEV row (1007). The record detail
view shows Prod vs Dev values side by side.

## 7. Sample data

`demo/` (prebuilt) + `scripts/seed_demo.py` (rebuild) hold 5
inputs and 5 outputs for TRS with real names and real column
lists, and 6 fictional members: 1001 Alice Anderson, 1002 Bob
Jones (inactive), 1003 Carol White, 1004 Dan (blank last name
-- the bad-record case), 1005 Eve Martin (inactive), 1006 Frank
Brown.

Inputs: `STG_TRS_D_DC_INDV` (6), `STG_TRS_D_INDV_ADDR` (6),
`STG_TRS_H_DC_INDV` (2), `STG_TRS_D_DC_RELATIONSHIPS` (2),
`LOOKUP_CODE_VALUE` (4).

Outputs (Prod side): `C_S_TRS_PTY` (6),
`C_S_TRS_PTY_RLE_PHN` (5), `STG_TRS_VALID_MEMBERS` (6),
`EXC_STG_BAD_REC_MEMB` (1: member 1004, blank last name),
`ZZ_UTL_UNMERGE_TREE_SRC_KEY` (2: inactive members 1002, 1005).

Prod outputs are built by the same derivation the demo
simulator uses (`derive_outputs` in `harness/demo.py`), with
planted differences off for Prod and on for Dev: member 1003
renamed, member 1005 dropped from the party output, member 1007
added, one extra Dev-only exception row; everything else
matches exactly.

Honesty note: the `ZZ_UTL_UNMERGE_TREE_SRC_KEY` columns
(`INDV_ID`, `SRC_KEY`, `TREE_LEVEL`, `PROCESSED_YN`) are sample
columns, not Oracle DDL -- replace them with the real column
list before using that entry against real Dev Oracle tables.
Everything else in the pack uses real Oracle column lists.
Input tables in this slice carry the columns the derivation
needs; expand them to full Oracle column lists when you expand
the registry (§8) -- the pattern is identical.

## 8. Adding a source or a table

Tables are data in `harness/catalog.py`, not code changes
elsewhere:

1. Add one `TableDef` to that source's `inputs` or `outputs`:
   name, kind, Oracle schema, columns as (name, type) pairs,
   and for outputs the PK the compare sorts and matches on. A
   PK-less output table still copies, but compares by counts
   only and forces the verdict to PARTIAL.
2. If Dev Oracle may truncate it in step C, add its name to
   the whitelist file.
3. Add a test row in `tests/test_harness.py` the same way the
   sample tables are covered (copy counts, compare status, or
   a whitelist refusal).

To add a source: add a `SourceDef` with its runner procedures
(keys are the workflow names step D accepts) and its table
lists. Until its tables are registered, copy/compare requests
for it return a 400 naming the gap instead of an empty run.

## 9. How the code is written (house rules, enforced by lint)

- Strongly typed: every function is annotated; `mypy` runs
  clean under `disallow_untyped_defs`. Pydantic models for API
  contracts, dataclasses for internal results, SQLAlchemy Core
  `Table` objects for database tables.
- Linted and formatted: `ruff check` and `ruff format --check`
  pass (rules E, F, I, UP, B, SIM; line length 100).
- No ORM, no mini-ORM: no session, no declarative model, no
  automap, no reflection, no query builder that hides SQL.
- No cleverness: one class moves rows, one function merges
  rows, one module per safety rule. If a function needs a
  comment to explain its trick, it has the wrong shape.

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Whitelist file not found` | Step C fails closed without the file. Create it, or point `WHITELIST_PATH` at the right one. |
| `NOT in the whitelist` naming tables, nothing truncated | Add those tables to the whitelist file, or remove them from the request. This is the safety gate working as designed. |
| `Refusing to run: Prod and Dev connections are identical` | `ORACLE_PROD_URL` equals `ORACLE_DEV_URL`. Fix the URLs -- step C must never run against Production. |
| `NOT_FOUND` for a table in step C | The table doesn't exist in Dev. Create it there first (Dev mirrors Production); step C never creates Dev tables. |
| `No tables registered for source ...` | That source's table list is empty (ECI/WIC/TTF/FSS/CRE today). Register its tables (§8). |
| `Demo mode is on but demo database file(s) are missing` | Run `python scripts/seed_demo.py` (from the project root). |
| Step D succeeds but step F shows everything one-sided / missing | The Dev schema still held rows from an earlier run, or (D) ran against a different schema than (E) reads. Re-run (D) with `"reset_outputs": true` and check `SNOWFLAKE_DATABASE` / `SNOWFLAKE_SCHEMA`. |
| A second (D) run changes nothing | Insert-only runners with existing-key guards suppress rows on re-runs. Same fix as above. |
| Verdict PARTIAL with COUNT_ONLY | A compared table has no PK in the registry. Register its PK (§8). |
| Verdict PARTIAL with MISSING_IN_DEV | The table is missing from `Dev_SQLite` -- usually (E) ran with a table filter that excluded it, or (D) never created it. |
| `Invalid SQLite filename` | File arguments must be bare filenames inside `SQLITE_DIR`, not paths. Use the filename step (B)/(E) returned. |
| Compare shows a difference in a float column that looks equal | Values compare on their shortest decimal string form (see DESIGN.md §5). For bit-exact float work, compare that table by another means. |

## 11. Limitations (stated plainly)

- No scheduler: step A is a precondition + a check, not a cron
  job. Confirm the 8 AM ETL finished by hand.
- The compare needs PKs; PK-less tables are count-only
  (PARTIAL verdict).
- Other sources' tables are not registered yet (runners only).
- The ZZ table's columns are sample columns (see §7).
- Diff detail is capped per table (`DIFF_CAP`); counts are not.
- Live Oracle/Snowflake drivers are not tested here; the demo
  proves harness logic, not live drivers. Treat the first live
  run as a driver test, with the demo's expected counts as the
  reference.
- API-key auth only; Streamlit has no auth. Run both locally,
  not on a shared server.
