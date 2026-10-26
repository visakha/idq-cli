"""SQLite test harness: run the REAL compare service against a
real (SQLite) database, instead of the FakeSnowflake dicts in
test_services.py.

Why this exists, and what it does NOT do:
  * The fake-repository tests prove the verdict *logic* (what
    MATCH / MISMATCH / PARTIAL mean).  They do not prove the
    repository's SQL: a fake's `key_difference` is Python set
    arithmetic, not EXCEPT, and its `coverage_count` is Python
    string-splitting, not SPLIT_PART.  This harness proves the
    SQL itself -- EXCEPT in both directions, COUNT(DISTINCT ...),
    the version-set compare, and the spine/coverage queries --
    against a real database engine, with no Snowflake, no Oracle,
    and no network.
  * It does NOT simulate the Snowflake ETL.  The ETL procedures
    do not exist yet (see the guide), so there is nothing to run
    here that could produce SNOWFLAKE rows.  Instead, each
    scenario's SQL file inserts BOTH sides by hand: the IDQ rows
    the daily IDQ run would have produced, and the SNOWFLAKE rows
    a correct (or faulty) ETL would have produced.  That is the
    whole point of the harness at this stage: it lets you test
    the compare -- the part that IS built -- against the success
    and failure shapes you expect the ETL to produce, before the
    ETL exists to produce them.  When the ETL lands, these same
    scenarios become the acceptance cases for it: replace a
    scenario's SNOWFLAKE inserts with "run the ETL, then compare"
    and the expected verdicts must not change.
  * It does NOT test the copy step or the ETL step.  Copy needs
    Oracle; ETL needs Snowflake procedures.  This harness is
    compare-only, by design.

How it works, in one paragraph:
  SQLite has no schemas, but the compare always asks for tables
  as TRS_ETL_WRK.<table> (the schema comes from settings).  The
  trick is ATTACH: an in-memory database is attached under the
  name TRS_ETL_WRK, so TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN is a real
  addressable table.  A StaticPool keeps the whole harness on
  ONE connection (otherwise each pooled connection would get
  its own empty :memory: database), and an event listener runs
  the ATTACH on connect.  All catalog tables (inputs + expected)
  are created in the attached schema from the explicit
  definitions in app/domain/tables.py -- the same definitions
  the copy/compare use -- so a scenario that forgets a table
  fails loudly instead of silently comparing nothing.

How to add a scenario (the pattern every test here follows):
  1. Add a SQL file in test_harness_data/ (project root, NOT
     tests/).  SQL lives there, not in Python, so a scenario is
     readable, diffable, and reusable outside pytest -- you can
     run the same file against a real Snowflake schema by hand.
     Header comments in the file MUST say: what it simulates,
     which side(s) it loads, and the expected verdict.
  2. Load it in a test with load_scenario() -- usually the
     common spine file first, then the scenario file.  The
     common spine file exists so a dimension scenario is not
     polluted by a spine mismatch it did not intend.
  3. Call run_compare() with a dimension filter (to isolate the
     scenario) or with no filter (to check the whole verdict),
     and assert on the DimensionCompare / SpineCompare objects
     -- counts, matched/oracle-only/snowflake-only keys, samples,
     version keys, and the verdict -- not just the verdict
     string.  A test that only asserts "MISMATCH" would pass
     for the wrong reason.

SQL files are executed with sqlite3's executescript(), so they
may contain -- comments and multiple INSERT statements.  They
must NOT contain DDL: tables are created by the harness.
"""

from __future__ import annotations

import pathlib

from sqlalchemy import create_engine, event
from sqlalchemy.pool import StaticPool

from app.core.config import settings
from app.domain import catalog
from app.domain.tables import table_for
from app.repositories.snowflake_repository import SnowflakeRepository

SCHEMA = settings.snowflake_schema  # TRS_ETL_WRK

# test_harness_data/ lives at the project root, next to tests/.
HARNESS_DATA_DIR = pathlib.Path(__file__).resolve().parent.parent / "test_harness_data"


def make_sqlite_engine(db_path: str | pathlib.Path | None = None):
    """SQLite engine, with TRS_ETL_WRK attached.

    db_path=None (the default, and what the unit tests use):
    in-memory, fresh per test, so scenarios can never leak
    rows into each other.  The engine is gone when the test
    ends, and so is the data -- by design.

    db_path=<a file> (persistent mode): the file IS the
    TRS_ETL_WRK database.  It is ATTACHed under that name, so
    the compare sees TRS_ETL_WRK.<table> exactly as before,
    but the tables and rows live in the file and survive after
    the engine is disposed: close the engine, reopen the file
    (with this function, or with sqlite3 / a DB browser), and
    the data is still there.  Tables are created only if
    missing, checked explicitly via
    inspect.get_table_names(schema=...): Table.create()
    with checkfirst=True does NOT see tables in an attached
    SQLite schema and would try to recreate them on reopen.
    Reopening an existing file therefore does NOT drop it --
    loading the same scenario twice will duplicate its rows,
    which is why build_persistent_db() has a fresh=True
    option that deletes the file first.  Use
    scripts/build_sqlite_harness_db.py to build such a file
    from scenario SQL, then point the API at it with
    SQLITE_HARNESS_DB_PATH and inspect it via GET /sqlite/tables.
    """
    engine = create_engine(
        "sqlite://",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    # ATTACH takes a literal filename, not a bound parameter, so
    # the path is quoted by doubling single quotes.  Paths here
    # come from the test / the builder script, never from an API
    # request (the inspection endpoint never ATTACHes at all --
    # it opens the file directly, read-only in effect).
    attached = ":memory:" if db_path is None else str(db_path).replace("'", "''")

    @event.listens_for(engine, "connect")
    def _attach(dbapi_conn, _record):
        # SQLite schema == attached database name.  Without this,
        # TRS_ETL_WRK.<table> would be "no such table".
        cursor = dbapi_conn.cursor()
        cursor.execute(f"ATTACH DATABASE '{attached}' AS {SCHEMA}")
        cursor.close()

    # Explicit existence check (see docstring): do not rely on
    # Table.create(checkfirst=True) for attached schemas.
    from sqlalchemy import inspect as _inspect

    existing = set(_inspect(engine).get_table_names(schema=SCHEMA))
    for spec in catalog.ALL_TABLES:
        if spec.name not in existing:
            table_for(spec.name, SCHEMA).create(engine)
    return engine


def build_persistent_db(db_path: str | pathlib.Path, *filenames: str, fresh: bool = False):
    """Build (or rebuild) a persistent harness file from scenario SQL.

    Returns the engine, already loaded.  Dispose it when done;
    the file stays on disk.  fresh=True deletes an existing file
    first -- without it, reloading a scenario into an existing
    file appends its rows a second time (tables themselves are
    not recreated on reopen, see make_sqlite_engine).
    """
    path = pathlib.Path(db_path)
    if fresh and path.exists():
        path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    engine = make_sqlite_engine(path)
    load_scenario(engine, *filenames)
    return engine


def load_scenario(engine, *filenames: str) -> None:
    """Execute one or more test_harness_data/*.sql files, in order.

    Files are loaded in the order given: load the common spine
    file first, then the scenario file, so the scenario's rows
    are the ones that decide the verdict.
    """
    raw_conn = engine.raw_connection()
    try:
        for filename in filenames:
            # Accept both forms: a bare name ("01_match_phones.sql",
            # resolved against test_harness_data/) and a path that
            # already exists ("test_harness_data/01_...sql" from the
            # project root, or an absolute path).  The builder
            # script passes the second form; the tests pass the
            # first.  Neither form may silently load nothing.
            given = pathlib.Path(filename)
            path = given if given.exists() else HARNESS_DATA_DIR / filename
            assert path.exists(), f"Harness data file missing: {path} (tried {filename!r})"
            raw_conn.executescript(path.read_text())
        raw_conn.commit()
    finally:
        raw_conn.close()


def sqlite_repository(engine) -> SnowflakeRepository:
    """The REAL SnowflakeRepository, pointed at SQLite.

    No fake, no subclass: the same repository class the API
    uses, with the same Core statements.  The only SQLite
    special-case in production code is the spine expression in
    coverage_count() (SUBSTR/INSTR instead of SPLIT_PART) --
    see that method's docstring.
    """
    return SnowflakeRepository(lambda: engine)


def harness_repo(*filenames: str, db_path: str | pathlib.Path | None = None):
    """One-call setup for most tests: engine + repo + loaded files.

    Returns (engine, repo).  The engine is returned so a test
    can run raw SQL checks against it if it needs to (e.g. to
    prove a row really is in the table, not just in a verdict).
    Pass db_path for the persistent (file-based) form; omit it
    for the default in-memory form.
    """
    engine = make_sqlite_engine(db_path)
    load_scenario(engine, *filenames)
    return engine, sqlite_repository(engine)
