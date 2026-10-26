#!/usr/bin/env python3
"""Build a persistent SQLite harness database file from scenario SQL.

Usage (from the project root):
    python scripts/build_sqlite_harness_db.py --db ./trs_harness.db \\
        --fresh 00_common_spine.sql 01_match_phones.sql
    SQLITE_HARNESS_DB_PATH=./trs_harness.db uvicorn app.main:app --host 127.0.0.1 --port 8000
    # then: GET /sqlite/tables (or open trs_harness.db in sqlite3 / a DB browser)

The file IS the TRS_ETL_WRK database: the harness ATTACHes it
under that name, so the compare sees TRS_ETL_WRK.<table>, and
the inspection endpoint opens the file directly and sees
<table>.  Same file, same rows.

--fresh deletes an existing file first.  Without it, loading a
scenario into an existing file APPENDS its rows a second time
(tables are created with checkfirst=True, so they are not
dropped on reopen) -- useful for stacking scenarios, dangerous
if you meant to rebuild.  When in doubt, use --fresh.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from app.repositories.sqlite_inspect_repository import list_sqlite_tables  # noqa: E402
from tests.sqlite_harness import build_persistent_db  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, help="SQLite file to build (e.g. ./trs_harness.db)")
    parser.add_argument("--fresh", action="store_true", help="Delete an existing file first")
    parser.add_argument("scenarios", nargs="+", help="test_harness_data/*.sql files, in load order")
    args = parser.parse_args()

    engine = build_persistent_db(args.db, *args.scenarios, fresh=args.fresh)
    engine.dispose()
    print(f"Built {args.db} from: {', '.join(args.scenarios)}")
    for info in list_sqlite_tables(args.db, "DATA_SOURCE"):
        grouped = f" {info.counts_by_discriminator}" if info.has_discriminator else ""
        print(f"  {info.table}: {info.row_count}{grouped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
