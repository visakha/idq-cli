"""Run repository: job history, nothing else.

This replaces the v2 control store module, as a repository class so it can
be injected like the other repositories.  The runs table is defined
explicitly here as a SQLAlchemy Core Table, and every method builds
a Core insert/select statement and returns a plain Pydantic model.
No ORM session, no declarative model, no reflection: the table shape
is in this file, in full, and it is created (CREATE TABLE IF NOT
EXISTS) when the repository is constructed.

The run store holds job history only -- never ETL data.  It is
SQLite by default (CONTROL_DB_URL); point it at any SQLAlchemy URL
if you want it elsewhere.  Its summary_json column holds the full
per-table / per-dimension summary of a run as JSON, so yesterday's
compare is still readable after today's copy.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, MetaData, String, Table, Text, desc, insert, select, text, update
from sqlalchemy.engine import Engine

from app.domain.models import RunRecord
from app.repositories.queries import SELECT_ONE_CONTROL

_METADATA = MetaData()

RUNS = Table(
    "runs",
    _METADATA,
    Column("id", String, primary_key=True),
    Column("run_type", String, nullable=False),  # copy | etl | compare
    Column("status", String, nullable=False),  # COMPLETED | FAILED | PARTIAL | PLANNED | RUNNING
    Column("started_at", DateTime, nullable=False),
    Column("finished_at", DateTime, nullable=True),
    Column("summary_json", Text, nullable=False, default="{}"),
    Column("message", Text, nullable=False, default=""),
)


def _row_to_record(row) -> RunRecord:
    mapping = dict(row._mapping)
    return RunRecord(
        id=mapping["id"],
        run_type=mapping["run_type"],
        status=mapping["status"],
        started_at=mapping["started_at"],
        finished_at=mapping["finished_at"],
        summary_json=mapping["summary_json"] or "{}",
        message=mapping["message"] or "",
    )


class RunRepository:
    """Job history store."""

    def __init__(self, engine: Engine) -> None:
        self._engine = engine
        _METADATA.create_all(engine, tables=[RUNS])

    def new_run(self, run_id: str, run_type: str) -> RunRecord:
        """Insert a RUNNING run and return it."""
        record = RunRecord(id=run_id, run_type=run_type, status="RUNNING")
        with self._engine.begin() as conn:
            conn.execute(
                insert(RUNS).values(
                    id=record.id,
                    run_type=record.run_type,
                    status=record.status,
                    started_at=record.started_at,
                    finished_at=None,
                    summary_json="{}",
                    message="",
                )
            )
        return record

    def finish_run(self, record: RunRecord, status: str, message: str, summary: object) -> RunRecord:
        """Mark a run finished, with its status, message and summary JSON."""
        finished = RunRecord(
            id=record.id,
            run_type=record.run_type,
            status=status,
            started_at=record.started_at,
            finished_at=datetime.now(timezone.utc),
            summary_json=json.dumps(summary, default=str),
            message=message,
        )
        with self._engine.begin() as conn:
            conn.execute(
                update(RUNS)
                .where(RUNS.c.id == record.id)
                .values(
                    status=finished.status,
                    finished_at=finished.finished_at,
                    summary_json=finished.summary_json,
                    message=finished.message,
                )
            )
        return finished

    def get_run(self, run_id: str) -> RunRecord | None:
        """One run by id, or None."""
        with self._engine.connect() as conn:
            row = conn.execute(select(RUNS).where(RUNS.c.id == run_id)).first()
        return _row_to_record(row) if row is not None else None

    def list_runs(
        self, run_type: str | None = None, status: str | None = None, limit: int = 50
    ) -> list[RunRecord]:
        """Recent runs, newest first, optionally filtered."""
        query = select(RUNS).order_by(desc(RUNS.c.started_at)).limit(limit)
        if run_type:
            query = query.where(RUNS.c.run_type == run_type)
        if status:
            query = query.where(RUNS.c.status == status)
        with self._engine.connect() as conn:
            rows = conn.execute(query).all()
        return [_row_to_record(row) for row in rows]

    def ping(self) -> None:
        """SELECT 1, for /health.  Raises on failure."""
        with self._engine.connect() as conn:
            conn.execute(text(SELECT_ONE_CONTROL))
