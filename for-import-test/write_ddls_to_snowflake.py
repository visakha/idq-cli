#!/usr/bin/env python3
"""Write DDL files to Snowflake, recursively, from zip(s) and/or folders.

Starting at each input root, the script walks the whole tree (root first,
then every child folder, directories and files in sorted order) and
executes every DDL statement it finds, then prints and optionally saves
a per-file report.

Usage (Windows Command Prompt shown; Linux/macOS identical apart from
paths):

  pip install snowflake-connector-python

  REM Dry run first: walks, splits, reports, touches nothing, needs no
  REM Snowflake connection and no connector install.
  python write_ddls_to_snowflake.py --dry-run ^
      --zip Snowflake_All_Sources_Bare_Bones_v2.1_COMPILED.zip ^
      --zip Snowflake_Deactivation_Reactivation_Bare_Bones_COMPILED.zip

  REM Live run into one schema (both bare-bones packages are safe in a
  REM single schema: no procedure/function name collides across sources,
  REM and the two packages' helper files are byte-identical).
  python write_ddls_to_snowflake.py ^
      --zip Snowflake_All_Sources_Bare_Bones_v2.1_COMPILED.zip ^
      --zip Snowflake_Deactivation_Reactivation_Bare_Bones_COMPILED.zip ^
      --database BAREBONES_COMPILE_DB --schema SCRIPT_TEST --create-schema ^
      --private-key-file C:\\keys\\vizy_rsa_key.p8 ^
      --report ddl_run_report.txt

  REM A folder that is already extracted works the same way:
  python write_ddls_to_snowflake.py --root .\\unzipped_package ^
      --database MYDB --schema MYSCHEMA --create-schema ^
      --private-key-file C:\\keys\\vizy_rsa_key.p8

Authentication: key-pair auth (the same unencrypted PKCS#8 private key
file used by snowsql's --private-key-path). Defaults below match the
account this script was built for; every one can be overridden.
The private key file can also be given with the SNOWFLAKE_PRIVATE_KEY_PATH
environment variable. The key itself is never printed or logged; only
the connector reads the file.

Target: --database and --schema are required for a live run. With
--create-schema, the script first runs CREATE DATABASE IF NOT EXISTS and
CREATE SCHEMA IF NOT EXISTS, then USEs them. Every object is created
with CREATE OR REPLACE from the source files, so re-running the script
overwrites same-named objects in the target schema. Use a scratch schema
first (see --dry-run).

What counts as DDL here, and what is skipped (all skips are reported):
  * Only *.sql files are considered. .md / .svg / .png / .dot and any
    other non-.sql file is skipped.
  * Files whose name starts with "run_" are snowsql wrappers, not DDL:
    they contain "!set" directives and CALL statements that would RUN
    procedures. They are skipped, never executed.
  * Any file containing a "!" directive line is skipped for the same
    reason.
  * Inside a .sql file, statements are split on ";" outside $$ bodies,
    quotes and comments (the same splitter used to validate these
    packages). Only statements starting with CREATE are executed. Any
    other top-level statement (CALL, INSERT, UPDATE, ...) is skipped
    individually and reported, so a stray non-DDL statement can never
    execute data changes through this script.

Prerequisite (not created by this script, on purpose): the lookup
functions in 02_snow_common_lookups.sql reference 7 objects
(V_LOOKUP_CODE_VALUE, REF_JUNK_NAME_LIST, REF_MATCHCODE_DESC,
RDM.REF_PHN_AREA_CD, EXC_LOOKUP_CODE_VALUE, LOOKUP_CODE_VALUE,
REF_DYLGHT_SVNGS_TM). If they do not exist yet, that one file fails
with the missing object named in the report, and everything else still
installs. Real definitions must be supplied; this script never invents
stub objects.

Exit code: 0 when every executed file succeeded, 1 when any file or
statement failed, 2 for usage errors. A failed file does not stop the
run by default (see --fail-fast); the report lists every failure.
"""

import argparse
import os
import shutil
import sys
import tempfile
import time
import zipfile

# Defaults match the account this script was built for; all overridable.
DEFAULT_ACCOUNT = "DOOPELI-LL99227"
DEFAULT_USER = "VIZY"
DEFAULT_ROLE = "ACCOUNTADMIN"
DEFAULT_WAREHOUSE = "SNOWFLAKE_LEARNING_WH"
DEFAULT_AUTHENTICATOR = "SNOWFLAKE_JWT"


def split_statements(sql):
    """Split SQL text on ';' outside $$ bodies, quotes, and comments.

    Returns only statements that contain real code (comment-only chunks
    are dropped).
    """
    stmts, buf = [], []
    i, n = 0, len(sql)
    in_dollar = in_quote = in_line = in_block = False
    while i < n:
        ch, nxt = sql[i], sql[i + 1] if i + 1 < n else ""
        if in_line:
            buf.append(ch)
            if ch == "\n":
                in_line = False
            i += 1
            continue
        if in_block:
            buf.append(ch)
            if ch == "*" and nxt == "/":
                buf.append(nxt)
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_dollar:
            buf.append(ch)
            if ch == "$" and nxt == "$":
                buf.append(nxt)
                in_dollar = False
                i += 2
                continue
            i += 1
            continue
        if in_quote:
            buf.append(ch)
            if ch == "'":
                if nxt == "'":
                    buf.append(nxt)
                    i += 2
                    continue
                in_quote = False
            i += 1
            continue
        if ch == "$" and nxt == "$":
            buf.append("$$")
            in_dollar = True
            i += 2
            continue
        if ch == "'":
            buf.append(ch)
            in_quote = True
            i += 1
            continue
        if ch == "/" and nxt == "*":
            buf.append("/*")
            in_block = True
            i += 2
            continue
        if ch == "-" and nxt == "-":
            buf.append("--")
            in_line = True
            i += 2
            continue
        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt and not all(
                line.strip().startswith("--") or not line.strip()
                for line in stmt.splitlines()
            ):
                stmts.append(stmt)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail and not all(
        line.strip().startswith("--") or not line.strip()
        for line in tail.splitlines()
    ):
        stmts.append(tail)
    return stmts


def strip_comments(stmt):
    """Remove -- comments (full-line and trailing) from one statement."""
    out = []
    for line in stmt.splitlines():
        if line.strip().startswith("--"):
            continue
        out.append(line.split("--", 1)[0] if "--" in line else line)
    return "\n".join(out)


def is_create_statement(stmt):
    """True when the statement's first code token is CREATE."""
    code = strip_comments(stmt).strip()
    return code[:6].upper() == "CREATE"


def collect_files(roots):
    """Walk every root recursively (sorted) -> list of (display, path).

    display is the path relative to its input root, prefixed with the
    input label so two inputs stay distinguishable in the report.
    """
    found = []
    for label, root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root)
                found.append((f"{label}/{rel}", full))
    return found


def classify_and_split(display, path):
    """Return (kind, statements_or_reason).

    kind: 'run' (list of statements to execute), 'skip' (reason string).
    """
    base = os.path.basename(path)
    if not base.lower().endswith(".sql"):
        return "skip", "not a .sql file"
    if base.lower().startswith("run_"):
        return "skip", "snowsql wrapper (contains CALL, not DDL)"
    text = open(path, encoding="utf-8").read()
    for line in text.splitlines():
        if line.lstrip().startswith("!"):
            return "skip", "contains a snowsql '!' directive, not plain DDL"
    return "run", split_statements(text)


def build_report(lines):
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Recursively write DDL files from zip(s)/folder(s) "
        "to Snowflake and report the results."
    )
    ap.add_argument("--zip", dest="zips", action="append", default=[],
                    help="Zip file to extract and walk (repeatable).")
    ap.add_argument("--root", dest="roots", action="append", default=[],
                    help="Already-extracted folder to walk (repeatable).")
    ap.add_argument("--account", default=DEFAULT_ACCOUNT)
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--role", default=DEFAULT_ROLE)
    ap.add_argument("--warehouse", default=DEFAULT_WAREHOUSE)
    ap.add_argument("--authenticator", default=DEFAULT_AUTHENTICATOR)
    ap.add_argument("--private-key-file",
                    default=os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH"),
                    help="Unencrypted PKCS#8 private key file "
                    "(or SNOWFLAKE_PRIVATE_KEY_PATH).")
    ap.add_argument("--database", help="Target database (live run).")
    ap.add_argument("--schema", help="Target schema (live run).")
    ap.add_argument("--create-schema", action="store_true",
                    help="CREATE DATABASE/SCHEMA IF NOT EXISTS first.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Walk, split and report only; no connection.")
    ap.add_argument("--fail-fast", action="store_true",
                    help="Stop at the first failed statement.")
    ap.add_argument("--report", help="Also write the report to this file.")
    args = ap.parse_args(argv)

    if not args.zips and not args.roots:
        ap.error("at least one --zip or --root is required")
    if not args.dry_run and (not args.database or not args.schema):
        ap.error("--database and --schema are required for a live run")
    if not args.dry_run and not args.private_key_file:
        ap.error("live run needs --private-key-file (or "
                 "SNOWFLAKE_PRIVATE_KEY_PATH)")

    started = time.time()
    tmpdirs = []
    walk_roots = []
    try:
        for z in args.zips:
            if not os.path.isfile(z):
                ap.error(f"zip not found: {z}")
            tmp = tempfile.mkdtemp(prefix="ddls_")
            tmpdirs.append(tmp)
            with zipfile.ZipFile(z) as zf:
                zf.extractall(tmp)
            walk_roots.append((os.path.basename(z), tmp))
        for r in args.roots:
            if not os.path.isdir(r):
                ap.error(f"root folder not found: {r}")
            walk_roots.append((os.path.basename(os.path.abspath(r)), r))

        files = collect_files(walk_roots)
        lines = [
            "DDL RUN REPORT",
            f"mode: {'DRY RUN (nothing executed)' if args.dry_run else 'LIVE'}",
            f"inputs: {', '.join(os.path.basename(z) for z in args.zips + args.roots) or '(none)'}",
        ]
        if not args.dry_run:
            lines.append(f"target: {args.database}.{args.schema}")
        lines.append(f"files walked: {len(files)}")
        lines.append("")

        # Classify everything first, so a dry run needs no connection
        # and a live run knows its full file list up front.
        plan = []  # (display, path, kind, payload)
        for display, path in files:
            kind, payload = classify_and_split(display, path)
            plan.append((display, path, kind, payload))
        n_exec = sum(1 for _, _, k, _ in plan if k == "run")
        n_skip = len(plan) - n_exec
        lines.append(f"files to execute: {n_exec}, files skipped: {n_skip}")
        lines.append("")

        conn = cur = None
        if not args.dry_run:
            try:
                import snowflake.connector
            except ImportError:
                print("ERROR: snowflake-connector-python is not installed. "
                      "Run: pip install snowflake-connector-python",
                      file=sys.stderr)
                return 2
            conn = snowflake.connector.connect(
                account=args.account, user=args.user,
                private_key_file=args.private_key_file,
                role=args.role, warehouse=args.warehouse,
                authenticator=args.authenticator, login_timeout=120,
            )
            cur = conn.cursor()
            try:
                if args.create_schema:
                    cur.execute(
                        f"CREATE DATABASE IF NOT EXISTS {args.database}")
                    cur.execute(
                        f"CREATE SCHEMA IF NOT EXISTS "
                        f"{args.database}.{args.schema}")
                cur.execute(f"USE DATABASE {args.database}")
                cur.execute(f"USE SCHEMA {args.schema}")
            except Exception as exc:  # noqa: BLE001 - fatal setup error
                print(f"ERROR: cannot prepare target: {exc}", file=sys.stderr)
                return 1

        results, errors, skipped = [], [], []
        stmt_total = stmt_ok = 0
        try:
            for display, _path, kind, payload in plan:
                if kind == "skip":
                    skipped.append((display, payload))
                    print(f"SKIP {display} ({payload})", flush=True)
                    continue
                stmts = payload
                file_ok = True
                ran = 0
                for idx, stmt in enumerate(stmts):
                    if not is_create_statement(stmt):
                        skipped.append(
                            (f"{display} [statement {idx}]",
                             "not a CREATE statement, not executed"))
                        print(f"SKIP-STATEMENT {display} [statement {idx}] "
                              f"({' '.join(stmt.split())[:80]})", flush=True)
                        continue
                    ran += 1
                    stmt_total += 1
                    if args.dry_run:
                        stmt_ok += 1
                        continue
                    try:
                        cur.execute(stmt)
                        stmt_ok += 1
                    except Exception as exc:  # noqa: BLE001 - report, continue
                        file_ok = False
                        errors.append({
                            "file": display, "stmt": idx,
                            "head": " ".join(stmt.split())[:160],
                            "error": str(exc),
                        })
                        print(f"FAIL {display} [statement {idx}]: {exc}",
                              flush=True)
                        if args.fail_fast:
                            break
                results.append((display, len(stmts), ran, file_ok))
                print(f"{'OK  ' if file_ok else 'FAIL'} {display} "
                      f"({ran} statements executed)", flush=True)
                if args.fail_fast and not file_ok:
                    break
        finally:
            if cur is not None:
                cur.close()
            if conn is not None:
                conn.close()

        n_ok = sum(1 for _, _, _, ok in results if ok)
        lines.append("")
        lines.append("SUMMARY")
        lines.append(f"files executed: {len(results)} "
                     f"({n_ok} OK, {len(results) - n_ok} FAILED)")
        lines.append(f"statements executed: {stmt_total} "
                     f"({stmt_ok} OK, {stmt_total - stmt_ok} FAILED)")
        lines.append(f"files skipped: {len(skipped)}")
        lines.append(f"errors: {len(errors)}")
        lines.append(f"elapsed: {time.time() - started:.1f}s")
        if errors:
            lines.append("")
            lines.append("ERRORS:")
            for e in errors:
                lines.append(f"  {e['file']} [statement {e['stmt']}]: "
                             f"{e['head']}")
                lines.append(f"    -> {e['error']}")
        if skipped:
            lines.append("")
            lines.append("SKIPPED:")
            for display, why in skipped:
                lines.append(f"  {display}: {why}")
        report = build_report(lines)
        print("")
        print(report, end="")
        if args.report:
            with open(args.report, "w", encoding="utf-8") as fh:
                fh.write(report)
            print(f"report written: {args.report}")
        return 0 if not errors else 1
    finally:
        for tmp in tmpdirs:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
