#!/usr/bin/env python3
"""Generate Snowflake DDL (one-time step A) from the Oracle DDL exports.

Usage:
    python scripts/generate_snowflake_ddl.py \
        --oracle-dir /path/to/unzipped/sql_Ora \
        --out-dir sql

    The Oracle exports are the four files from sql_Ora.zip:
        STG_EXPORT_OCT_16.sql      -> schema STAGING
        LDG_EXPORT_OCT_16.sql      -> schema LANDING (not used by this ETL)
        MDM_STG_EXPORT_OCT_16.sql  -> schema HHS_MDM, C_S_* staging tables
        MDM_BASE_EXPORT_OCT_16.sql -> schema HHS_MDM, C_B_* base tables

    Only the tables the Snowflake ETL actually reads or writes are
    emitted (see NEEDED in catalog.py logic below).  Everything else in
    the exports -- backups, BAK_* tables, TTF tables, other domains --
    is deliberately left out.  Re-run this script when a fresh Oracle
    export arrives; it overwrites sql/01_*.sql, sql/02_*.sql and
    sql/03_*.sql, and it never overwrites sql/04_missing_tables.sql
    (that file is hand-maintained until the missing objects are supplied).

Type mapping (Oracle -> Snowflake):
    VARCHAR2(n BYTE|CHAR) -> VARCHAR(n)   (Snowflake counts characters;
        review any column holding multi-byte data -- see the guide)
    CHAR(n CHAR|BYTE)     -> CHAR(n)
    NUMBER(p,s)           -> NUMBER(p,s)
    NUMBER(*,0)           -> NUMBER(38,0)
    NUMBER (bare)         -> NUMBER(38,0)  (every bare NUMBER in the
        needed tables is an integer ID / sequence / flag -- verified
        by inspection; if a future export adds a decimal bare NUMBER,
        change it by hand and note it here)
    DATE                  -> DATE
    TIMESTAMP(n)          -> TIMESTAMP_NTZ(n)
    DEFAULT CURRENT_TIMESTAMP -> DEFAULT CURRENT_TIMESTAMP()
    DEFAULT sysdate           -> DEFAULT CURRENT_TIMESTAMP()
    DEFAULT <literal>         -> kept as-is (e.g. DEFAULT 0, DEFAULT 'CMX')
    Grants, tablespaces, storage clauses, indexes and constraints other
    than the column list are dropped: this DDL is for a comparison
    sandbox, not a production MDM rebuild.  No PRIMARY KEYs are created
    on purpose -- the ETL is insert-only and the comparison is by
    PKEY_SRC_OBJECT / natural key sets, not by enforced keys.
    (If you later want PKs, add them after the parity run, not before:
    a PK would change ETL failure behaviour on duplicate inserts.)

Snowflake layout used by the FastAPI copy job (v5, see config.py):
    Database MDM_ETL_TRS, one schema TRS_ETL_WRK -- all input and target
    tables live there.  Target (expected) tables carry an extra
    Snowflake-only column, DATA_SOURCE VARCHAR(20) NOT NULL
    DEFAULT 'SNOWFLAKE', appended as the last column: the copy writes
    'IDQ' into it, the Snowflake ETL writes 'SNOWFLAKE' (or relies
    on the default, which is why the default is 'SNOWFLAKE' and not
    NULL -- an existing procedure that does not name the column
    still produces the correct side).  Input tables have no
    discriminator column: they are the shared Oracle input.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

SOURCE = "TRS"  # Change for another source: ECI, WIC, TTF, CRE, FSS.
SCHEMA = f"{SOURCE}_ETL_WRK"  # The schema name carries the source (see config.py).

# ---------------------------------------------------------------------------
# The table list.  Keep this in sync with app/catalog.py.
#   name -> (oracle_schema, copy_role)
#   copy_role: "input"    = Oracle source, copied to MDM_ETL_TRS_SRC and MDM_ETL_TRS_WORK
#              "expected" = IDQ target, copied to MDM_ETL_TRS_IDQ only;
#                           MDM_ETL_TRS_WORK gets an EMPTY table of the same shape
# ---------------------------------------------------------------------------
INPUT_TABLES: dict[str, str] = {
    # STAGING inputs
    "STG_TRS_CD_REF": "STAGING",
    "STG_TRS_CV_ED_MCI_EDG_INDV": "STAGING",
    "STG_TRS_DC_CASES": "STAGING",
    "STG_TRS_DC_CASE_INDV": "STAGING",
    "STG_TRS_DC_PRIMARY_PAYEE": "STAGING",
    "STG_TRS_D_CV_DC_MCI_ALIAS": "STAGING",
    "STG_TRS_D_CV_DC_MCI_INDV": "STAGING",
    "STG_TRS_D_CV_DC_MRG_SPRT_INDV": "STAGING",
    "STG_TRS_D_CV_ED_MCI_EDG_INDV": "STAGING",
    "STG_TRS_D_CV_MCI_EDG_INDV_TOA": "STAGING",
    "STG_TRS_D_DC_ALIAS": "STAGING",
    "STG_TRS_D_DC_CASES": "STAGING",
    "STG_TRS_D_DC_INDV": "STAGING",
    "STG_TRS_D_DC_PRIMARY_PAYEE": "STAGING",
    "STG_TRS_D_DC_RELATIONSHIPS": "STAGING",
    "STG_TRS_D_DC_RELATIONSHIPS_A": "STAGING",
    "STG_TRS_D_INDV_ADDR": "STAGING",
    "STG_TRS_D_IN_MANAGED_CARE": "STAGING",
    "STG_TRS_D_LU_TOA": "STAGING",
    "STG_TRS_H_DC_INDV": "STAGING",
    "EXC_LOOKUP_CODE_VALUE": "STAGING",
    "LOOKUP_CODE_VALUE": "STAGING",
    "REF_DYLGHT_SVNGS_TM": "STAGING",
    # HHS_MDM base (cross-reference) inputs
    "C_B_PTY_RLE_ALT_ID": "HHS_MDM",
    "C_B_PTY_RLE_ALT_ID_XREF": "HHS_MDM",
    "C_B_PTY_RLE_REL_XREF": "HHS_MDM",
}

EXPECTED_TABLES: dict[str, str] = {
    # HHS_MDM staging targets
    "C_S_LU_TOA": "HHS_MDM",
    "C_S_TRS_PTY": "HHS_MDM",
    "C_S_TRS_PTY_MNG_ATTR": "HHS_MDM",
    "C_S_TRS_PTY_NM": "HHS_MDM",
    "C_S_TRS_PTY_RLE": "HHS_MDM",
    "C_S_TRS_PTY_RLE_ADDR": "HHS_MDM",
    "C_S_TRS_PTY_RLE_ALT_ID": "HHS_MDM",
    "C_S_TRS_PTY_RLE_EADDR": "HHS_MDM",
    "C_S_TRS_PTY_RLE_PHN": "HHS_MDM",
    "C_S_TRS_PTY_RLE_PLN": "HHS_MDM",
    "C_S_TRS_PTY_RLE_REL": "HHS_MDM",
    "C_S_TRS_PTY_RLE_REL_PROV": "HHS_MDM",
    "C_S_TRS_PTY_RLE_TOA": "HHS_MDM",
    # STAGING targets / intermediates
    "DQM_ADDRESS": "STAGING",
    "EXC_STG_BAD_REC_MEMB": "STAGING",
    "STG_TRS_DEACTIVATED_RELATIONSHIPS": "STAGING",
    "STG_TRS_DEACTIVED_MEMBERS": "STAGING",
    "STG_TRS_D_UNQ_ADDR": "STAGING",
    "STG_TRS_VALID_MEMBERS": "STAGING",
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

def parse_oracle_tables(oracle_dir: pathlib.Path) -> dict[str, tuple[str, list[tuple[str, str]]]]:
    """Return {table_name: (oracle_schema, [(column, oracle_type), ...])}."""
    tables: dict[str, tuple[str, list[tuple[str, str]]]] = {}
    for path in sorted(oracle_dir.glob("*.sql")):
        text = path.read_text(errors="ignore")
        for schema, name, body in _table_bodies(text):
            if name in tables and tables[name][0] != schema:
                # Same name in two Oracle schemas (e.g. BAK tables) --
                # the first file wins only for tables we do not need;
                # needed tables are unique to one schema, checked below.
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
            tables[name] = (schema, columns)
    return tables


def translate_type(oracle_type: str) -> str:
    """Translate one Oracle column type to Snowflake. Raises on unknown."""
    upper = oracle_type.upper().strip()
    # Defaults are handled by the caller; strip them here for matching.
    default = ""
    if " DEFAULT " in upper:
        base, default = upper.split(" DEFAULT ", 1)
        upper = base.strip()
        if default == "SYSDATE":
            default = "CURRENT_TIMESTAMP()"
        elif default == "CURRENT_TIMESTAMP":
            default = "CURRENT_TIMESTAMP()"
        # literal defaults (0, 'CMX', 4, 1) are kept as-is
    m = re.match(r"VARCHAR2\((\d+)\s+(?:BYTE|CHAR)\)", upper)
    if m:
        out = f"VARCHAR({m.group(1)})"
    elif (m := re.match(r"CHAR\((\d+)\s+(?:BYTE|CHAR)\)", upper)) is not None:
        out = f"CHAR({m.group(1)})"
    elif (m := re.match(r"NUMBER\((\d+),\s*(\d+)\)", upper)) is not None:
        out = f"NUMBER({m.group(1)},{m.group(2)})"
    elif upper in ("NUMBER(*,0)", "NUMBER"):
        out = "NUMBER(38,0)"
    elif upper == "DATE":
        out = "DATE"
    elif (m := re.match(r"TIMESTAMP\s*\((\d+)\)", upper)) is not None:
        out = f"TIMESTAMP_NTZ({m.group(1)})"
    elif upper == "TIMESTAMP":
        out = "TIMESTAMP_NTZ"
    else:
        raise ValueError(f"Unmapped Oracle type: {oracle_type!r}")
    return f"{out} DEFAULT {default}" if default else out


def render_table(sf_schema: str, name: str, columns: list[tuple[str, str]], oracle_schema: str, add_discriminator: bool = False) -> str:
    lines = [
        f"-- {name}: Oracle {oracle_schema}.{name}, translated (see header).",
        f"CREATE TABLE IF NOT EXISTS {sf_schema}.{name} (",
    ]
    rendered = []
    for col, otype in columns:
        try:
            rendered.append(f"    {col} {translate_type(otype)}")
        except ValueError as exc:
            raise ValueError(f"{name}.{col}: {exc}") from exc
    if add_discriminator:
        rendered.append("    DATA_SOURCE VARCHAR(20) NOT NULL DEFAULT 'SNOWFLAKE'")
    lines.append(",\n".join(rendered))
    lines.append(");")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--oracle-dir", required=True, type=pathlib.Path)
    parser.add_argument("--out-dir", required=True, type=pathlib.Path)
    args = parser.parse_args()

    tables = parse_oracle_tables(args.oracle_dir)
    missing: list[str] = []
    for name, schema in {**INPUT_TABLES, **EXPECTED_TABLES}.items():
        if name not in tables:
            missing.append(name)
        elif tables[name][0] != schema:
            print(f"WARNING: {name} found in {tables[name][0]}, expected {schema}", file=sys.stderr)
    if missing:
        print(f"ERROR: not in Oracle exports: {', '.join(missing)}", file=sys.stderr)
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)

    # One file, one schema (v5): inputs + targets in TRS_ETL_WRK.
    # Targets get the DATA_SOURCE discriminator column; inputs do not.
    all_tables = {**INPUT_TABLES, **EXPECTED_TABLES}
    header = (
        f"-- {SCHEMA} -- all {SOURCE} input and target tables, one schema\n"
        "-- Generated by scripts/generate_snowflake_ddl.py from the Oracle\n"
        "-- exports in sql_Ora.zip.  Do not hand-edit: re-run the script\n"
        "-- when a fresh export arrives.  Apply once (step A).\n\n"
    )
    blocks = [
        render_table(SCHEMA, name, tables[name][1], tables[name][0],
                     add_discriminator=(name in EXPECTED_TABLES))
        for name in sorted(all_tables)
    ]
    (args.out_dir / "01_etl_wrk.sql").write_text(header + "\n\n".join(blocks) + "\n")
    print(f"wrote 01_etl_wrk.sql: {len(all_tables)} tables "
          f"({len(INPUT_TABLES)} inputs, {len(EXPECTED_TABLES)} targets with DATA_SOURCE)")

    print("NOT generated here (see sql/04_missing_tables.sql): "
          "V_LOOKUP_CODE_VALUE, REF_JUNK_NAME_LIST, REF_MATCHCODE_DESC, "
          "REF_PHN_AREA_CD -- not present in the Oracle exports.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
