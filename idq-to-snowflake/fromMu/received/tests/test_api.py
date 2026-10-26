"""API tests: dry-run copy and health, no Oracle/Snowflake needed."""

import uuid

from fastapi.testclient import TestClient
from sqlalchemy import create_engine



def _client(tmp_path):
    # Inject a temp-database run repository via FastAPI's dependency
    # overrides -- the v3 way.  No monkeypatching of globals, and the
    # real trs_compare.db is never touched by tests.
    from sqlalchemy import create_engine

    from app.api.dependencies import get_run_repository
    from app.main import app
    from app.repositories.run_repository import RunRepository

    engine = create_engine(f"sqlite:///{tmp_path}/test.db")
    app.dependency_overrides[get_run_repository] = lambda: RunRepository(engine)
    return TestClient(app)


def test_health_without_db_checks(tmp_path):
    client = _client(tmp_path)
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["control_db"] == "ok"
    assert body["oracle"] == "not checked"
    assert body["snowflake"] == "not checked"


def test_copy_dry_run_copies_nothing(tmp_path):
    client = _client(tmp_path)
    resp = client.post("/runs/copy", json={"dry_run": True})
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "PLANNED"
    assert body["results"], "Dry-run plan should list tables"
    missing = [r for r in body["results"] if r["missing_from_exports"]]
    assert sorted(r["table"] for r in missing) == [
        "REF_JUNK_NAME_LIST",
        "REF_MATCHCODE_DESC",
        "REF_PHN_AREA_CD",
        "V_LOOKUP_CODE_VALUE",
    ]


def test_copy_dry_run_with_unknown_table_rejected(tmp_path):
    client = _client(tmp_path)
    resp = client.post("/runs/copy", json={"dry_run": True, "tables": ["NO_SUCH_TABLE"]})
    # An unknown table name must be rejected (400) before any database
    # is touched -- it can never reach a SQL statement, because table
    # names are only ever taken from the catalog allowlist.
    assert resp.status_code == 400


def test_get_run_after_dry_run(tmp_path):
    client = _client(tmp_path)
    run_id = client.post("/runs/copy", json={"dry_run": True}).json()["run_id"]
    resp = client.get(f"/runs/{run_id}")
    assert resp.status_code == 200
    assert resp.json()["run_id"] == run_id


def test_list_runs(tmp_path):
    client = _client(tmp_path)
    client.post("/runs/copy", json={"dry_run": True})
    resp = client.get("/runs")
    assert resp.status_code == 200
    assert len(resp.json()) >= 1


def test_run_repository_round_trip_without_fastapi(tmp_path):
    # The run repository on its own: explicit Core table, Pydantic
    # models in and out, no ORM session anywhere.
    from app.repositories.run_repository import RunRepository

    engine = create_engine(f"sqlite:///{tmp_path}/control.db")
    repo = RunRepository(engine)
    record = repo.new_run(str(uuid.uuid4()), "copy")
    assert record.status == "RUNNING"
    finished = repo.finish_run(record, "COMPLETED", "done", {"a": 1})
    assert finished.status == "COMPLETED"
    assert finished.message == "done"
    fetched = repo.get_run(record.id)
    assert fetched is not None and fetched.status == "COMPLETED"
    assert repo.list_runs()[0].id == record.id


def test_dry_run_unknown_table_leaves_no_orphan_run(tmp_path):
    client = _client(tmp_path)
    resp = client.post("/runs/copy", json={"dry_run": True, "tables": ["NO_SUCH_TABLE"]})
    assert resp.status_code == 400
    # The failed validation must not leave a RUNNING run behind.
    assert client.get("/runs").json() == []


def test_compare_run_is_readable_via_get_run(tmp_path):
    # Regression test for the v3 bug: a compare run's summary is a
    # dict, and GET /runs/{id} used to fail validating it as a list.
    from app.api.dependencies import get_snowflake_repository
    from app.main import app
    from tests.test_services import FakeSnowflake, _phone_rows, _spine_rows

    from app.core.config import settings as _settings

    store = _spine_rows()
    store[(_settings.snowflake_schema, "C_S_TRS_PTY_RLE_PHN")] = (
        [{**r, "DATA_SOURCE": _settings.discriminator_idq_value} for r in _phone_rows()]
        + [{**r, "DATA_SOURCE": _settings.discriminator_snowflake_value} for r in _phone_rows()]
    )
    app.dependency_overrides[get_snowflake_repository] = lambda: FakeSnowflake(store)
    try:
        client = _client(tmp_path)
        resp = client.post("/runs/compare", json={"dimensions": ["Phones"]})
        assert resp.status_code == 200
        assert resp.json()["verdict"] == "MATCH"
        run_id = resp.json()["run_id"]
        got = client.get(f"/runs/{run_id}")
        assert got.status_code == 200
        assert got.json()["run_id"] == run_id
    finally:
        app.dependency_overrides.pop(get_snowflake_repository, None)




def test_docs_served_from_local_bundle_not_cdn(tmp_path):
    # /docs must be the locally served Swagger UI: its JS/CSS come
    # from /swagger-static (this server), not from a CDN, and the
    # bundle file itself must be reachable.
    client = _client(tmp_path)
    resp = client.get("/docs")
    assert resp.status_code == 200
    assert "/swagger-static/swagger-ui-bundle.js" in resp.text
    assert "/swagger-static/swagger-ui.css" in resp.text
    assert "unpkg.com" not in resp.text
    assert "cdn.jsdelivr.net" not in resp.text
    bundle = client.get("/swagger-static/swagger-ui-bundle.js")
    assert bundle.status_code == 200
    # OpenAPI itself is unaffected by the docs change, except for
    # its version: it must be 3.0.3, not FastAPI's default 3.1.0,
    # because the bundled Swagger UI 4.15.5 only renders
    # swagger 2.0 / openapi 3.0.n.  A 3.1.0 spec makes the UI
    # show "Unable to render this definition".
    spec = client.get("/openapi.json")
    assert spec.status_code == 200
    assert spec.json()["openapi"] == "3.0.3"
    assert spec.json()["info"]["title"] == "TRS Compare API"
    # API key is a declared security scheme, so Swagger UI shows
    # an Authorize button for it (X-API-Key header).
    schemes = spec.json()["components"]["securitySchemes"]
    assert any(s.get("name") == "X-API-Key" for s in schemes.values())
