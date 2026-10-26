"""Typed models for the TRS compare API -- Pydantic only, no ORM.

Design, stated plainly because the previous version got this wrong:
  * There is NO ORM model in this project.  No SQLModel tables, no
    declarative models, no session.  The one local table (runs) is
    defined explicitly in app/repositories/run_repository.py as a Core Table,
    and RunRepository converts its rows to the RunRecord model below.
  * ETL tables are NOT models at all.  They are explicit column lists
    in app/domain/tables.py (generated, checked in), and queries over
    them are built with SQLAlchemy Core's fluent select/insert/except
    API in the services.  A table is data + a fluent query, not a
    class with a session attached to it.
  * Everything the API sends or receives is a Pydantic model below,
    so every endpoint's contract is typed and visible in /docs.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Run record (Pydantic model; the table lives in run_repository.py)
# ---------------------------------------------------------------------------
class RunRecord(BaseModel):
    """One API run: a copy, an ETL run, or a compare."""

    id: str
    run_type: str  # "copy" | "etl" | "compare"
    status: str  # "COMPLETED" | "FAILED" | "PARTIAL" | "PLANNED" | "RUNNING"
    started_at: datetime = Field(default_factory=utcnow)
    finished_at: datetime | None = None
    summary_json: str = "{}"
    message: str = ""


# ---------------------------------------------------------------------------
# Repository result models (internal, also used by the services)
# ---------------------------------------------------------------------------
class KeyDifference(BaseModel):
    """Keys present on one side of a set compare but not the other."""

    count: int
    sample: list[str] = []


# ---------------------------------------------------------------------------
# API request models
# ---------------------------------------------------------------------------
class CopyRequest(BaseModel):
    """POST /runs/copy.  tables=None means 'all tables in catalog order'."""

    tables: list[str] | None = Field(default=None, description="Oracle table names to copy; None = all")
    dry_run: bool = Field(default=False, description="If true, return the plan only; copy nothing")
    run_label: str | None = None


class EtlRequest(BaseModel):
    """POST /runs/etl."""

    workflows: list[str] = Field(default=["toa", "ongoing"], description="Subset/order of ['toa', 'ongoing']; default runs TOA catalogue first, then Ongoing")
    # No reset flag in v5: the ETL step ALWAYS deletes
    # DATA_SOURCE='SNOWFLAKE' rows from the target tables before
    # calling the runners (IDQ rows are preserved -- it is a DELETE
    # by discriminator, never a TRUNCATE).  The old reset flag
    # (truncate WORK) has no meaning now that there is no WORK schema.
    copy_run_id: str | None = Field(default=None, description="Optional: the copy run this ETL run is based on, for the audit trail only")


class CompareRequest(BaseModel):
    """POST /runs/compare."""

    domains: list[str] | None = Field(default=None, description="Filter by domain, e.g. ['Member']; None = all")
    dimensions: list[str] | None = Field(default=None, description="Filter by dimension, e.g. ['Phones', 'Addresses']; None = all")
    sample_limit: int = Field(default=20, ge=0, le=200, description="How many oracle-only / snowflake-only keys to include as samples per dimension")
    copy_run_id: str | None = Field(default=None, description="Optional: the copy run being compared, for the audit trail only")


# ---------------------------------------------------------------------------
# API response models
# ---------------------------------------------------------------------------
class TableCopyResult(BaseModel):
    table: str
    oracle_schema: str | None
    copy_role: str
    status: str  # "COPIED" | "RESET_EMPTY" | "SKIPPED_MISSING" | "FAILED"
    oracle_row_count: int | None = None
    snowflake_row_count: int | None = None
    destinations: list[str] = []
    message: str = ""


class RunResponse(BaseModel):
    run_id: str
    run_type: str
    status: str
    message: str = ""
    started_at: datetime
    finished_at: datetime | None = None
    # Per-table results (copy), per-workflow results (etl), or the
    # compare summary dict {verdict, dimensions, spine} (compare) --
    # see the endpoint's docs.  This is Any, not list, on purpose:
    # a compare run's summary is a dict, and forcing it into a list
    # made GET /runs/{id} fail for compare runs (v3 bug, fixed 3.1).
    results: Any = []
    snowflake_job_run_id: str | None = None


class DimensionCompare(BaseModel):
    domain: str
    dimension: str
    table: str
    compare_key: list[str]
    oracle_row_count: int
    snowflake_row_count: int
    count_diff: int  # snowflake - oracle
    matched_keys: int
    oracle_only_keys: int
    snowflake_only_keys: int
    oracle_only_sample: list[str] = []
    snowflake_only_sample: list[str] = []
    # For PKEY tables, the (PKEY, VERSION_SEQ) set compare.  None for
    # tables without VERSION_SEQ.
    version_matched_keys: int | None = None
    version_oracle_only_keys: int | None = None
    version_snowflake_only_keys: int | None = None
    message: str = ""


class SpineCompare(BaseModel):
    spine: str
    oracle_keys: int
    snowflake_keys: int
    matched_keys: int
    oracle_only_keys: int
    snowflake_only_keys: int
    oracle_only_sample: list[str] = []
    snowflake_only_sample: list[str] = []
    # Per-dimension coverage: distinct spine keys present in that
    # dimension, oracle vs snowflake.  A dimension whose coverage
    # differs is a dimension whose rows do not line up with the spine,
    # even if its total row count happens to match.
    coverage: list[dict[str, Any]] = []


class CompareResponse(BaseModel):
    run_id: str
    status: str
    message: str = ""
    started_at: datetime
    finished_at: datetime | None = None
    dimensions: list[DimensionCompare] = []
    spine: list[SpineCompare] = []
    # Headline verdict, computed in compare_service.py:
    # "MATCH" = every dimension count and key set matches;
    # "MISMATCH" = at least one does not; "PARTIAL" = some dimensions
    # could not be compared (e.g. a table missing in one schema).
    verdict: str = "UNKNOWN"


class SqliteTableInfo(BaseModel):
    """One table in a SQLite harness file, as GET /sqlite/tables reports it.

    counts_by_discriminator is None for tables without the
    discriminator column (inputs): there is nothing to group by,
    and reporting an empty dict would be ambiguous with "the
    table is empty".  For tables with it, the dict maps each
    DATA_SOURCE value to its row count, and row_count is the
    sum of those counts.
    """

    table: str
    row_count: int
    has_discriminator: bool
    counts_by_discriminator: dict[str, int] | None = None


class HealthResponse(BaseModel):
    status: str
    control_db: str
    oracle: str
    snowflake: str
    message: str = ""
