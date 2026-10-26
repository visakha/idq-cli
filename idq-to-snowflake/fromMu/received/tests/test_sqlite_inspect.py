"""Tests for the file-based SQLite harness and GET /sqlite/tables.

Two things are proved here, separately:
  1. Persistence: a harness file built once still has its rows
     after the engine is disposed and the file is reopened --
     both through the harness (ATTACH view) and through a plain
     sqlite3 open (direct view).  In-memory engines cannot
     prove this, because their data dies with the engine.
  2. Inspection: GET /sqlite/tables lists what is actually in
     the file, with counts grouped by DATA_SOURCE for tables
     that have that column, and a plain total for tables that
     do not -- and it 404s (without creating a file) when the
     database is unconfigured or missing.
"""

import sqlite3

import pytest

from app.core.config import settings
from app.repositories.sqlite_inspect_repository import list_sqlite_tables
from tests.sqlite_harness import harness_repo, load_scenario, make_sqlite_engine
from tests.test_api import _client


def test_file_harness_persists_after_engine_disposed(tmp_path):
    # Build a file, dispose the engine, then prove the rows are
    # still there -- first by reopening through the harness
    # (the ATTACH view the compare uses), then by a plain
    # sqlite3 open (the direct view a DB browser would see).
    db_path = tmp_path / "harness.db"
    engine, _repo = harness_repo("00_common_spine.sql", "01_match_phones.sql", db_path=db_path)
    engine.dispose()
    assert db_path.exists()

    engine2 = make_sqlite_engine(db_path)
    try:
        with engine2.connect() as conn:
            count = conn.exec_driver_sql(
                "SELECT COUNT(*) FROM TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN"
            ).scalar_one()
        assert count == 4  # 2 IDQ + 2 SNOWFLAKE
    finally:
        engine2.dispose()

    direct = sqlite3.connect(str(db_path))
    try:
        count = direct.execute("SELECT COUNT(*) FROM C_S_TRS_PTY_RLE_PHN").fetchone()[0]
        assert count == 4
    finally:
        direct.close()


def test_file_harness_reopen_keeps_compare_verdict(tmp_path):
    # Persistence is only useful if the reopened file still
    # compares the same way -- i.e. the file is a faithful
    # snapshot, not just a list of table names.
    from app.services import compare_service

    db_path = tmp_path / "harness.db"
    engine, _repo = harness_repo("00_common_spine.sql", "01_match_phones.sql", db_path=db_path)
    engine.dispose()
    engine2, repo2 = harness_repo(db_path=db_path)
    try:
        # No scenario files on reopen: the file already has them.
        _dims, _spine, verdict = compare_service.run_compare(repo2, None, ["Phones"], 20)
        assert verdict == "MATCH"
    finally:
        engine2.dispose()


def test_inspect_groups_by_discriminator_and_reports_plain_total(tmp_path):
    # Phones (a target, has DATA_SOURCE) -> grouped counts.
    # STG_TRS_CD_REF (an input, no DATA_SOURCE) -> plain total,
    # counts_by_discriminator=None (not an empty dict, which
    # would be ambiguous with "table is empty").
    db_path = tmp_path / "harness.db"
    engine, _repo = harness_repo("00_common_spine.sql", "01_match_phones.sql", db_path=db_path)
    try:
        with engine.begin() as conn:
            conn.exec_driver_sql(
                "INSERT INTO TRS_ETL_WRK.STG_TRS_CD_REF (REF_ID, TABLENAME, CODE, DESCRIPTION) "
                "VALUES (1, 'T', 'A', 'alpha')"
            )
    finally:
        engine.dispose()

    by_table = {info.table: info for info in list_sqlite_tables(str(db_path), "DATA_SOURCE")}
    phones = by_table["C_S_TRS_PTY_RLE_PHN"]
    assert phones.row_count == 4
    assert phones.has_discriminator is True
    assert phones.counts_by_discriminator == {"IDQ": 2, "SNOWFLAKE": 2}
    code_ref = by_table["STG_TRS_CD_REF"]
    assert code_ref.row_count == 1
    assert code_ref.has_discriminator is False
    assert code_ref.counts_by_discriminator is None
    # Every catalog table is present in the file, even empty ones.
    assert "C_S_TRS_PTY" in by_table


def test_load_scenario_accepts_path_form_as_well_as_bare_name(tmp_path):
    # Regression guard for the builder bug: passing
    # "test_harness_data/01_match_phones.sql" (a path that exists
    # from the project root) must load the same rows as the bare
    # name, not silently load nothing.
    from tests.sqlite_harness import HARNESS_DATA_DIR, load_scenario, make_sqlite_engine

    engine = make_sqlite_engine()
    try:
        load_scenario(engine, "00_common_spine.sql", str(HARNESS_DATA_DIR / "01_match_phones.sql"))
        with engine.connect() as conn:
            count = conn.exec_driver_sql(
                "SELECT COUNT(*) FROM TRS_ETL_WRK.C_S_TRS_PTY_RLE_PHN"
            ).scalar_one()
        assert count == 4
    finally:
        engine.dispose()


def test_inspect_missing_file_raises_and_creates_nothing(tmp_path):
    missing = tmp_path / "does_not_exist.db"
    with pytest.raises(FileNotFoundError):
        list_sqlite_tables(str(missing), "DATA_SOURCE")
    # The whole point of raising: a missing file must not be
    # silently created as an empty database.
    assert not missing.exists()


def test_api_sqlite_tables_endpoint(tmp_path):
    # The endpoint reads the CONFIGURED file only: set it for
    # this test, and restore it afterwards (settings is a
    # process-wide singleton).
    db_path = tmp_path / "harness.db"
    engine, _repo = harness_repo("00_common_spine.sql", "01_match_phones.sql", db_path=db_path)
    engine.dispose()
    previous = settings.sqlite_harness_db_path
    settings.sqlite_harness_db_path = str(db_path)
    try:
        client = _client(tmp_path)
        resp = client.get("/sqlite/tables")
        assert resp.status_code == 200
        by_table = {row["table"]: row for row in resp.json()}
        phones = by_table["C_S_TRS_PTY_RLE_PHN"]
        assert phones["row_count"] == 4
        assert phones["counts_by_discriminator"] == {"IDQ": 2, "SNOWFLAKE": 2}
    finally:
        settings.sqlite_harness_db_path = previous


def test_api_sqlite_tables_endpoint_unconfigured_and_missing(tmp_path):
    previous = settings.sqlite_harness_db_path
    client = _client(tmp_path)
    try:
        settings.sqlite_harness_db_path = None
        resp = client.get("/sqlite/tables")
        assert resp.status_code == 404
        assert "not configured" in resp.json()["detail"]

        settings.sqlite_harness_db_path = str(tmp_path / "nope.db")
        resp = client.get("/sqlite/tables")
        assert resp.status_code == 404
        assert "not found" in resp.json()["detail"]
        assert not (tmp_path / "nope.db").exists()
    finally:
        settings.sqlite_harness_db_path = previous
