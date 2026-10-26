"""Read-only inspection of a SQLite harness database file.

This is deliberately NOT a SnowflakeRepository method, and it
does not use the API's Snowflake connection at all.  The
harness file is a standalone SQLite database (see
tests/sqlite_harness.py: the file IS the TRS_ETL_WRK database),
so inspecting it means opening the file itself, listing its
tables, and counting rows -- with the counts grouped by the
discriminator column when a table has one.  That is a
different job from comparing, and it belongs in its own small
module, using Python's sqlite3 directly: no SQLAlchemy schema,
no ATTACH, no engine to configure.

Safety, stated plainly:
  * The file path comes from configuration
    (SQLITE_HARNESS_DB_PATH), never from a request.  The route
    takes no path parameter, so a caller cannot point this at
    an arbitrary file on the server.
  * The file is never created here: a missing file raises
    FileNotFoundError (the route turns it into 404) instead of
    silently creating an empty database and reporting zero
    tables -- an empty database is a lie about a missing one.
  * The connection is put in query-only mode after opening,
    so even a bug in this module cannot write to the file.
  * Table names come from sqlite_master, not from a request,
    and identifiers are quoted by doubling double-quotes.
    The discriminator column name comes from configuration,
    not from a request, and is checked against each table's
    actual columns (PRAGMA table_info) before it is used --
    a table without that column simply reports a total count,
    with counts_by_discriminator=None.
"""

from __future__ import annotations

import pathlib
import sqlite3

from app.domain.models import SqliteTableInfo


def _quote_identifier(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def list_sqlite_tables(db_path: str, discriminator_column: str) -> list[SqliteTableInfo]:
    """Every table in the file, with row counts.

    Tables are listed alphabetically, including tables that are
    not in the catalog -- the point is to show what is actually
    in the file, not what the catalog says should be there.
    Internal SQLite tables (sqlite_sequence, etc.) are excluded.
    For a table WITH the discriminator column, counts are
    grouped by that column's value (e.g. {"IDQ": 2,
    "SNOWFLAKE": 2}); a NULL discriminator value, should one
    ever occur, is reported under the key "<NULL>".  For a
    table WITHOUT it (inputs, which carry no discriminator),
    only the total is reported.
    """
    path = pathlib.Path(db_path)
    if not path.exists():
        raise FileNotFoundError(f"SQLite harness database not found: {db_path}")
    conn = sqlite3.connect(str(path))
    try:
        conn.execute("PRAGMA query_only = ON")
        tables = [
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
                "ORDER BY name"
            )
        ]
        result: list[SqliteTableInfo] = []
        for table in tables:
            columns = {row[1] for row in conn.execute(f"PRAGMA table_info({_quote_identifier(table)})")}
            if discriminator_column in columns:
                grouped = {
                    ("<NULL>" if value is None else str(value)): count
                    for value, count in conn.execute(
                        f"SELECT {_quote_identifier(discriminator_column)}, COUNT(*) "
                        f"FROM {_quote_identifier(table)} "
                        f"GROUP BY {_quote_identifier(discriminator_column)}"
                    )
                }
                result.append(SqliteTableInfo(
                    table=table,
                    row_count=sum(grouped.values()),
                    has_discriminator=True,
                    counts_by_discriminator=grouped,
                ))
            else:
                total = conn.execute(f"SELECT COUNT(*) FROM {_quote_identifier(table)}").fetchone()[0]
                result.append(SqliteTableInfo(
                    table=table,
                    row_count=total,
                    has_discriminator=False,
                    counts_by_discriminator=None,
                ))
        return result
    finally:
        conn.close()
