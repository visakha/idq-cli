#!/usr/bin/env python3
"""Generate app/domain/tables.py: explicit table definitions, checked in.

This is the anti-reflection script.  It reads the Oracle DDL exports
once, at generation time, and writes out a Python module that lists
every column of every table the ETL reads or writes, with its type,
as plain data.  Nothing in the running API inspects a database schema
at runtime (no automap, no MetaData.reflect, no INFORMATION_SCHEMA
lookup for column lists).  If a table changes in Oracle, re-run this
script (and generate_snowflake_ddl.py), review the diff, and commit
both -- the change is then visible in code review, not hidden in a
runtime reflection step.

Usage:
    python scripts/generate_tables.py \
        --oracle-dir /path/to/unzipped/sql_Ora \
        --out app/domain/tables.py

The four objects missing from the exports are included with the
columns the Snowflake lookup functions actually query (see
sql/04_missing_tables.sql for the full story).  They are marked
MISSING in the generated file so they cannot be mistaken for
Oracle-derived definitions.
"""

from __future__ import annotations

import argparse
import pathlib
import re

# Reuse the table lists from the DDL generator by importing its
# constants (it has no side effects on import).
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from generate_snowflake_ddl import EXPECTED_TABLES, INPUT_TABLES  # noqa: E402

# Columns the Snowflake lookup functions query, for the four objects
# missing from the Oracle exports.  All VARCHAR: the helpers only ever
# compare / return them as strings.
MISSING_COLUMNS: dict[str, list[tuple[str, str]]] = {
    "V_LOOKUP_CODE_VALUE": [
        ("CODE_TYPE", "String"),
        ("SRC_SYS", "String"),
        ("SRC_CODE_VALUE", "String"),
        ("MSTR_CODE_VALUE", "String"),
    ],
    "REF_JUNK_NAME_LIST": [
        ("NAME", "String"),
        ("EDIT_LIMITATION", "String"),
    ],
    "REF_MATCHCODE_DESC": [
        ("MATCH_CODE", "String"),
        ("DESCRIPTION", "String"),
    ],
    "REF_PHN_AREA_CD": [
        ("NPA_ID", "String"),
        ("SERVICE", "String"),
        ("IN_SERVICE", "String"),
        ("IN_SERVICE_DT", "Date"),
        ("COUNTRY", "String"),
    ],
}



def _table_bodies(text: str):
    """Yield (oracle_schema, table_name, column-list body) for each
    CREATE TABLE, using balanced-paren scanning, NOT a regex body.

    The old regex captured the body up to the first closing
    paren followed by a semicolon.  That is wrong
    for tables whose DDL has a clause after the closing paren, e.g.
    ``) CACHE ;``: the regex then ran on past the GRANTs and into
    the NEXT table's column list, so LOOKUP_CODE_VALUE shipped
    with its own 11 columns plus the next table's 10 columns
    (with different lengths) -- duplicate column names that make
    both the Table object and the Snowflake DDL invalid.  The
    harness creating every catalog table is what caught it.
    Balanced scanning stops at the paren that actually closes
    the column list, whatever follows it.
    """
    for match in re.finditer(r'CREATE TABLE "([^"]+)"\."([^"]+)"\s*\(', text):
        schema, name = match.groups()
        start = match.end()  # just after the opening paren
        depth = 1
        i = start
        while i < len(text) and depth > 0:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            i += 1
        if depth != 0:
            raise ValueError(f"Unbalanced parentheses in CREATE TABLE {schema}.{name}")
        yield schema, name, text[start:i - 1]

def parse_oracle_tables(oracle_dir: pathlib.Path) -> dict[str, list[tuple[str, str]]]:
    tables: dict[str, list[tuple[str, str]]] = {}
    for path in sorted(oracle_dir.glob("*.sql")):
        text = path.read_text(errors="ignore")
        for _schema, name, body in _table_bodies(text):
            if name in tables:
                continue
            columns: list[tuple[str, str]] = []
            parts: list[str] = []
            depth = 0
            current = ""
            for ch in body:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                if ch == "," and depth == 0:
                    parts.append(current)
                    current = ""
                else:
                    current += ch
            if current.strip():
                parts.append(current)
            for part in parts:
                col_match = re.match(r'\s*"([^"]+)"\s+(.+)$', part, re.S)
                if col_match:
                    columns.append((col_match.group(1), " ".join(col_match.group(2).split())))
            _names = [c for c, _ in columns]
            if len(set(_names)) != len(_names):
                raise ValueError(f"Duplicate columns in {name}: {_names}")
            tables[name] = columns
    return tables


def core_type(oracle_type: str) -> str:
    """Oracle column type -> SQLAlchemy Core type expression (as text)."""
    upper = oracle_type.upper().strip()
    if " DEFAULT " in upper:
        upper = upper.split(" DEFAULT ", 1)[0].strip()
    m = re.match(r"VARCHAR2\((\d+)\s+(?:BYTE|CHAR)\)", upper)
    if m:
        return f"String({m.group(1)})"
    if (m := re.match(r"CHAR\((\d+)\s+(?:BYTE|CHAR)\)", upper)) is not None:
        return f"CHAR({m.group(1)})"
    if (m := re.match(r"NUMBER\((\d+),\s*(\d+)\)", upper)) is not None:
        return f"Numeric({m.group(1)}, {m.group(2)})"
    if upper in ("NUMBER(*,0)", "NUMBER"):
        return "Numeric(38, 0)"
    if upper == "DATE":
        return "Date"
    if re.match(r"TIMESTAMP\s*\(\d+\)", upper) or upper == "TIMESTAMP":
        return "DateTime"
    raise ValueError(f"Unmapped Oracle type: {oracle_type!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--oracle-dir", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args()

    oracle_tables = parse_oracle_tables(args.oracle_dir)
    all_names = sorted({**INPUT_TABLES, **EXPECTED_TABLES})
    missing = [n for n in all_names if n not in oracle_tables]
    if missing:
        print(f"ERROR: not in Oracle exports: {', '.join(missing)}")
        return 1

    lines: list[str] = []
    lines.append('"""Explicit table definitions for the TRS compare job.')
    lines.append("")
    lines.append("Generated by scripts/generate_tables.py from the Oracle DDL")
    lines.append("exports.  Checked in, reviewed as code, and NEVER built by")
    lines.append("reflecting a database at runtime: no automap, no")
    lines.append("MetaData.reflect(), no INFORMATION_SCHEMA column lookup.")
    lines.append("If a table changes in Oracle, re-run the generator, review")
    lines.append("the diff, and commit it -- the change is then visible in")
    lines.append("code review, not hidden in a runtime step.")
    lines.append("")
    lines.append("Why a data table and not one Table object per table?  The")
    lines.append("same table name exists in Oracle schemas and in Snowflake's")
    lines.append("TRS_ETL_WRK schema, and a SQLAlchemy Column object can belong to")
    lines.append("only one Table.")
    lines.append("So this module stores column lists as data, and table_for()")
    lines.append("builds a fresh Table from them for the schema you ask for.")
    lines.append("Defaults are intentionally NOT carried here: the DDL in")
    lines.append("sql/ keeps them; the copy job inserts explicit values for")
    lines.append("every column, so a query-time default would never fire.")
    lines.append('"""')
    lines.append("")
    lines.append("from __future__ import annotations")
    lines.append("")
    lines.append("from sqlalchemy import CHAR, Column, Date, DateTime, MetaData, Numeric, String, Table")
    lines.append("")
    lines.append("")
    lines.append("# name -> [(column_name, core_type), ...]")
    lines.append("COLUMN_TYPES: dict[str, list[tuple[str, object]]] = {")
    for name in all_names:
        lines.append(f"    {name!r}: [")
        for col, otype in oracle_tables[name]:
            lines.append(f'        ({col!r}, {core_type(otype)}),')
        if name in EXPECTED_TABLES:
            # v5 discriminator: Snowflake-only column, not in Oracle.
            # Appended last, matching sql/01_etl_wrk.sql.  The copy
            # writes 'IDQ' into it; the ETL writes 'SNOWFLAKE'.
            lines.append("        ('DATA_SOURCE', String(20)),")
        lines.append("    ],")
    lines.append("")
    lines.append("    # --- Missing from the Oracle exports (see sql/04_missing_tables.sql).")
    lines.append("    # Columns are only what the Snowflake lookup functions query.")
    lines.append("    # Replace with the full Oracle definition when it is supplied.")
    for name, cols in MISSING_COLUMNS.items():
        lines.append(f"    {name!r}: [")
        for col, typ in cols:
            lines.append(f'        ({col!r}, {typ}),')
        lines.append("    ],")
    lines.append("}")
    lines.append("")
    lines.append("")
    lines.append("def table_for(name: str, schema: str) -> Table:")
    lines.append('    """Build an explicit Table for `name` in `schema`.')
    lines.append("")
    lines.append("    A fresh Table (and fresh Columns) is built on every call,")
    lines.append("    so the same table name can be used in several schemas")
    lines.append("    in one process without sharing Column objects.")
    lines.append('    """')
    lines.append("    if name not in COLUMN_TYPES:")
    lines.append('        raise KeyError(f"Unknown table: {name!r}. See app/domain/catalog.py.")')
    lines.append("    return Table(")
    lines.append("        name,")
    lines.append("        MetaData(),")
    lines.append("        *(Column(col, typ) for col, typ in COLUMN_TYPES[name]),")
    lines.append("        schema=schema,")
    lines.append("    )")
    lines.append("")
    lines.append("")
    lines.append("def column_names(name: str) -> list[str]:")
    lines.append('    """Column names for `name`, in DDL order."""')
    lines.append("    return [col for col, _typ in COLUMN_TYPES[name]]")
    lines.append("")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines))
    print(f"wrote {args.out}: {len(all_names)} Oracle tables + {len(MISSING_COLUMNS)} missing tables")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
