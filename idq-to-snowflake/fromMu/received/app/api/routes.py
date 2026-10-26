"""API endpoints: the operator's three daily steps, plus status.

The operator's morning flow (see the guide):
  1. Check, by hand, that the production IDQ ETL has completed.
  2. POST /runs/copy     -- Oracle -> Snowflake (inputs + IDQ rows in TRS_ETL_WRK).
  3. POST /runs/etl      -- run the Snowflake ETL in TRS_ETL_WRK.
  4. POST /runs/compare  -- IDQ targets vs Snowflake targets, by
     domain/dimension, with spine coverage.
  5. GET /runs/{run_id}  -- any step's status and messages, any time.

Routes are thin, in the Spring MVC sense: validate the request,
call a service with the repositories it needs (injected via Depends
-- see api/dependencies.py), record the run, return the response.
No route touches a database directly, and no route builds SQL.

Every POST returns a RunResponse (or CompareResponse for compare)
with a status and a human-readable message, even on failure -- the
operator should never have to read a stack trace to know what
happened.  Failures are also recorded in the run store, so a failed
run is visible in GET /runs after the fact.

Authentication: if API_KEY is set in .env, every endpoint except
/health requires the X-API-Key header.  Snowflake SSO is separate:
it is how the API itself authenticates to Snowflake (see config.py).
"""

from __future__ import annotations

import json
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Security
from fastapi.security import APIKeyHeader

from app.api.dependencies import (
    get_oracle_repository,
    get_run_repository,
    get_snowflake_repository,
)
from app.core.config import settings
from app.domain import catalog
from app.domain.models import (
    CompareRequest,
    CompareResponse,
    CopyRequest,
    EtlRequest,
    HealthResponse,
    RunResponse,
    SqliteTableInfo,
)
from app.repositories import sqlite_inspect_repository
from app.repositories.oracle_repository import OracleRepository
from app.repositories.run_repository import RunRepository
from app.repositories.snowflake_repository import SnowflakeRepository
from app.services import compare_service, copy_service, etl_service

router = APIRouter()


# Declared as a security scheme (not a plain Header) so Swagger UI
# shows an Authorize button and sends the key as X-API-Key on
# try-it-out requests.  Behaviour is unchanged: auto_error=False
# means a missing key reaches the check below as None, and the
# 401 message is exactly the one it has always been.
_api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def _require_api_key(x_api_key: str | None = Security(_api_key_header)) -> None:
    if settings.api_key and x_api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="Missing or incorrect X-API-Key header.")


def _to_response(record) -> RunResponse:
    return RunResponse(
        run_id=record.id,
        run_type=record.run_type,
        status=record.status,
        message=record.message,
        started_at=record.started_at,
        finished_at=record.finished_at,
        results=json.loads(record.summary_json) if record.summary_json else [],
    )


@router.get("/health", response_model=HealthResponse)
def health(
    runs: Annotated[RunRepository, Depends(get_run_repository)],
    check_db: bool = False,
) -> HealthResponse:
    """Liveness, plus optional Oracle/Snowflake connectivity checks.

    Without ?check_db=true this touches only the run store, so it
    is safe for a load balancer.  With it, it pings both databases
    and reports each result separately -- a failure in one does not
    hide the other, and no credentials are ever returned.

    Note: the Oracle and Snowflake repositories are NOT declared as
    dependencies here on purpose.  Constructing them would call
    oracle_engine()/snowflake_engine(), which raise when those
    databases are unconfigured -- even for a plain health check that
    does not need them.  They are constructed inside the check_db
    branch only, where a failure is reported, not raised.
    """
    run_repo = runs
    control = "ok"
    try:
        run_repo.ping()
    except Exception as exc:
        control = f"error: {type(exc).__name__}: {exc}"
    oracle_status = "not checked"
    snowflake_status = "not checked"
    if check_db:
        try:
            get_oracle_repository().ping()
            oracle_status = "ok"
        except Exception as exc:
            oracle_status = f"error: {type(exc).__name__}: {exc}"
        try:
            get_snowflake_repository().ping()
            snowflake_status = "ok"
        except Exception as exc:
            snowflake_status = f"error: {type(exc).__name__}: {exc}"
    overall = "ok" if control == "ok" and (not check_db or (oracle_status == "ok" and snowflake_status == "ok")) else "degraded"
    return HealthResponse(status=overall, control_db=control, oracle=oracle_status, snowflake=snowflake_status)


@router.get("/config/tables", dependencies=[Depends(_require_api_key)])
def list_tables(_: None = Depends(_require_api_key)) -> dict:
    """The catalog: every table the copy/compare jobs know about."""
    return {
        "input_tables": [t.model_dump() for t in catalog.INPUT_TABLES],
        "expected_tables": [t.model_dump() for t in catalog.EXPECTED_TABLES],
        "missing_from_oracle_exports": [t.name for t in catalog.ALL_TABLES if t.missing_from_exports],
        "snowflake": {
            "database": settings.snowflake_database,
            "schema": settings.snowflake_schema,
            "common_database": settings.snowflake_common_database,
            "common_schema": settings.snowflake_common_schema,
            "discriminator_column": settings.discriminator_column,
            "discriminator_idq_value": settings.discriminator_idq_value,
            "discriminator_snowflake_value": settings.discriminator_snowflake_value,
        },
    }


@router.get("/sqlite/tables", response_model=list[SqliteTableInfo], dependencies=[Depends(_require_api_key)])
def list_sqlite_tables(_: None = Depends(_require_api_key)) -> list[SqliteTableInfo]:
    """List the tables in the SQLite harness database file, with row counts.

    Read-only inspection for the lightweight testing workflow:
    build a persistent harness file with
    scripts/build_sqlite_harness_db.py, point the API at it with
    SQLITE_HARNESS_DB_PATH, and this endpoint shows what is
    actually in the file -- every table, alphabetically, with
    its total row count, and for tables that carry the
    discriminator column (DATA_SOURCE), the count grouped by
    that column (IDQ vs SNOWFLAKE).  Tables without the column
    (inputs) report only the total, with
    counts_by_discriminator=null.

    The path comes from configuration only -- there is no path
    parameter, so a caller cannot point this at an arbitrary
    file.  If SQLITE_HARNESS_DB_PATH is unset, or the file does
    not exist, this is a 404 with a message saying what to set
    or build, not an empty list pretending the database is empty.
    This endpoint does not touch Snowflake, Oracle, or the run
    store; it reads the harness file directly.
    """
    db_path = settings.sqlite_harness_db_path
    if not db_path:
        raise HTTPException(
            status_code=404,
            detail=(
                "SQLite harness database is not configured. "
                "Set SQLITE_HARNESS_DB_PATH to a harness file built with "
                "scripts/build_sqlite_harness_db.py (see the guide, "
                "SQLite harness section)."
            ),
        )
    try:
        return sqlite_inspect_repository.list_sqlite_tables(db_path, settings.discriminator_column)
    except FileNotFoundError:
        raise HTTPException(
            status_code=404,
            detail=(
                f"SQLite harness database not found: {db_path}. "
                "Build it first with scripts/build_sqlite_harness_db.py."
            ),
        )


@router.post("/runs/copy", response_model=RunResponse, dependencies=[Depends(_require_api_key)])
def post_copy(
    request: CopyRequest,
    runs: Annotated[RunRepository, Depends(get_run_repository)],
    oracle: Annotated[OracleRepository, Depends(get_oracle_repository)],
    snowflake: Annotated[SnowflakeRepository, Depends(get_snowflake_repository)],
) -> RunResponse:
    """Endpoint 1: copy Oracle -> Snowflake after the IDQ run.

    Dry run: returns the plan (tables, roles, destinations) with
    status PLANNED and copies nothing.  Use it to check the table
    list before a real run, or in tests without any database.
    """
    run_repo = runs
    if request.dry_run:
        # Validate BEFORE creating the run: a 400 here must not leave
        # an orphan RUNNING run in the store (v3 bug, fixed 3.1).
        try:
            specs = catalog.tables_for_copy(request.tables)
        except KeyError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        record = run_repo.new_run(str(uuid.uuid4()), "copy")
        plan = [
            {
                "table": s.name, "oracle_schema": s.oracle_schema,
                "copy_role": s.copy_role,
                "missing_from_exports": s.missing_from_exports,
            }
            for s in specs
        ]
        finished = run_repo.finish_run(record, "PLANNED", "Dry run: nothing copied.", plan)
        response = _to_response(finished)
        response.results = plan
        return response
    record = run_repo.new_run(str(uuid.uuid4()), "copy")
    try:
        results, overall = copy_service.run_copy(
            oracle,
            snowflake,
            request.tables,
        )
    except Exception as exc:
        finished = run_repo.finish_run(record, "FAILED", f"{type(exc).__name__}: {exc}", [])
        return _to_response(finished)
    copied = sum(1 for r in results if r.status == "COPIED")
    message = (
        f"Copy {overall}: {copied}/{len(results)} tables copied. "
        + "; ".join(f"{r.table}: {r.message}" for r in results if r.status in ("FAILED", "SKIPPED_MISSING"))
    )
    if request.run_label:
        message = f"Label: {request.run_label}. " + message
    finished = run_repo.finish_run(record, overall, message, [r.model_dump() for r in results])
    response = _to_response(finished)
    response.results = [r.model_dump() for r in results]
    return response


@router.post("/runs/etl", response_model=RunResponse, dependencies=[Depends(_require_api_key)])
def post_etl(
    request: EtlRequest,
    runs: Annotated[RunRepository, Depends(get_run_repository)],
    snowflake: Annotated[SnowflakeRepository, Depends(get_snowflake_repository)],
) -> RunResponse:
    """Endpoint 2: run the Snowflake ETL in TRS_ETL_WRK.

    The SNOWFLAKE side of every target table is deleted first
    (IDQ rows preserved), then the workflows run in the requested
    order (default: TOA, then Ongoing).  A failure stops later
    workflows; the response names the failed workflow and its
    error, and the Snowflake job run id (when one was returned) so
    the step story can be read from JOB_CONTROL_ETL in COMMON.
    """
    run_repo = runs
    record = run_repo.new_run(str(uuid.uuid4()), "etl")
    try:
        results, overall, job_run_id = etl_service.run_etl(
            snowflake, request.workflows
        )
    except Exception as exc:
        finished = run_repo.finish_run(record, "FAILED", f"{type(exc).__name__}: {exc}", [])
        return _to_response(finished)
    message = "; ".join(f"{r['workflow']}: {r['status']}" for r in results)
    if request.copy_run_id:
        message = f"Based on copy run {request.copy_run_id}. " + message
    finished = run_repo.finish_run(record, overall, message, results)
    response = _to_response(finished)
    response.results = results
    response.snowflake_job_run_id = job_run_id
    return response


@router.post("/runs/compare", response_model=CompareResponse, dependencies=[Depends(_require_api_key)])
def post_compare(
    request: CompareRequest,
    runs: Annotated[RunRepository, Depends(get_run_repository)],
    snowflake: Annotated[SnowflakeRepository, Depends(get_snowflake_repository)],
) -> CompareResponse:
    """Endpoint 3: compare IDQ rows (DATA_SOURCE='IDQ') vs Snowflake rows
    (DATA_SOURCE='SNOWFLAKE') in the same TRS_ETL_WRK target tables.

    Returns one row per dimension (counts, PKEY key sets, version
    sets, samples of differing keys) plus the spine section.  The
    verdict is MATCH / MISMATCH / PARTIAL -- see compare_service.py
    for the exact definition.  A MISMATCH is a successful compare
    with a negative answer, not an API error: it returns 200 with
    verdict=MISMATCH and the differing keys, so the operator can act
    on it directly.
    """
    run_repo = runs
    record = run_repo.new_run(str(uuid.uuid4()), "compare")
    try:
        dims, spine, verdict = compare_service.run_compare(
            snowflake,
            request.domains, request.dimensions, request.sample_limit,
        )
    except Exception as exc:
        finished = run_repo.finish_run(record, "FAILED", f"{type(exc).__name__}: {exc}", [])
        return CompareResponse(
            run_id=finished.id, status="FAILED",
            message=f"{type(exc).__name__}: {exc}",
            started_at=finished.started_at, finished_at=finished.finished_at,
            verdict="PARTIAL",
        )
    status = "COMPLETED" if verdict in ("MATCH", "MISMATCH") else "PARTIAL"
    message = f"Compare verdict: {verdict} over {len(dims)} dimensions."
    if request.copy_run_id:
        message = f"Based on copy run {request.copy_run_id}. " + message
    summary = {
        "verdict": verdict,
        "dimensions": [d.model_dump() for d in dims],
        "spine": [s.model_dump() for s in spine],
    }
    finished = run_repo.finish_run(record, status, message, summary)
    return CompareResponse(
        run_id=finished.id, status=status, message=message,
        started_at=finished.started_at, finished_at=finished.finished_at,
        dimensions=dims, spine=spine, verdict=verdict,
    )


@router.get("/runs", response_model=list[RunResponse], dependencies=[Depends(_require_api_key)])
def list_runs(
    runs: Annotated[RunRepository, Depends(get_run_repository)],
    run_type: str | None = None, status: str | None = None, limit: int = 50,
) -> list[RunResponse]:
    """Recent runs, newest first, optionally filtered."""
    records = (runs).list_runs(run_type=run_type, status=status, limit=limit)
    return [_to_response(r) for r in records]


@router.get("/runs/{run_id}", response_model=RunResponse, dependencies=[Depends(_require_api_key)])
def get_run(
    run_id: str,
    runs: Annotated[RunRepository, Depends(get_run_repository)],
) -> RunResponse:
    """One run's status, message, and full summary."""
    record = (runs).get_run(run_id)
    if record is None:
        raise HTTPException(status_code=404, detail=f"No run with id {run_id!r}.")
    return _to_response(record)
