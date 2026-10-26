# test_harness_data — SQLite compare scenarios

SQL scenario files for the SQLite test harness
(`tests/sqlite_harness.py`, tests in `tests/test_sqlite_harness.py`).
SQL lives here, not in Python, so a scenario is readable,
diffable, and can be run by hand against a real Snowflake
schema: replace `TRS_ETL_WRK.` with the real schema and run
the file, then compare the two DATA_SOURCE sides.

## Files

| File | What it simulates | Expected verdict (filtered) |
|---|---|---|
| `00_common_spine.sql` | Shared setup: same spine both sides. Load FIRST, except with 07. | — (setup) |
| `01_match_phones.sql` | Correct ETL, Phones | MATCH |
| `02_match_demographics.sql` | Correct ETL, Demographics (with 01, no filter: full MATCH) | MATCH |
| `03_missing_on_snowflake.sql` | ETL dropped a phone (3\|Member) | MISMATCH, oracle-only 1 |
| `04_extra_on_snowflake.sql` | ETL over-produced a phone (4\|Member, outside spine) | MISMATCH, snowflake-only 1 |
| `05_version_mismatch.sql` | PKEYs match, a timeline version (2\|Member v2) is missing | MISMATCH, version-oracle-only 1 |
| `06_duplicate_keys.sql` | Same phone key twice on the IDQ side | MISMATCH + duplicate note |
| `07_spine_gap.sql` | Valid-member spine missing member 3; Phones perfect | MISMATCH via spine only |
| `08_coverage_gap.sql` | Names covers 3 members IDQ, 2 Snowflake | MISMATCH, coverage 3 vs 2 |
| `09_exceptions_match.sql` | Same bad records flagged both sides | MATCH (+ "no unique key" note) |
| `10_pre_etl_empty_snowflake.sql` | Copy done, ETL not run yet — Snowflake side empty | MISMATCH, snowflake count 0 |

## Rules for adding a scenario

1. Header comment MUST say: what it simulates, which sides
   it loads, and the expected verdict/counts. A scenario
   without an expected outcome is not a test.
2. Load `00_common_spine.sql` first, unless the scenario IS
   about the spine (like 07) — then load its own spine.
3. Insert only the columns a scenario needs. All other
   columns are nullable in `app/domain/tables.py`, so a
   scenario stays readable instead of listing 23 columns.
4. Never put DDL in a scenario file. Tables are created by
   the harness from `app/domain/tables.py`.
5. Do NOT "fix" scenario 10 by adding Snowflake rows. It
   documents the pre-ETL state. When the ETL is ready, retire
   it — its expected verdict flips to MATCH only once the
   ETL actually fills the Snowflake side.

## File-based (persistent) form

In-memory is the default for tests. For inspection by hand,
build a file and keep it:

```bash
python scripts/build_sqlite_harness_db.py --db ./trs_harness.db \
    --fresh 00_common_spine.sql 01_match_phones.sql
SQLITE_HARNESS_DB_PATH=./trs_harness.db uvicorn app.main:app
curl http://127.0.0.1:8000/sqlite/tables
```

Reopening a file does not drop it (tables are created only
if missing), so without `--fresh` a scenario loaded twice
appears twice. `GET /sqlite/tables` is read-only, reads
only the configured file, and 404s when it is unset/missing.
