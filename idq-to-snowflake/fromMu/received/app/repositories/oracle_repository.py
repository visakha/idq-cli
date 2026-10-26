"""Oracle repository: the IDQ side, read-only.

This is the Spring Data JDBC repository idea, without the framework:
a small class whose methods are named for the operations the job
actually needs, each implemented explicitly.  There is no derived
query (no method-name parsing), no generic CRUD base class, and no
ORM session.  The repository owns the connection handling; callers
own the business logic.

Methods:
  * count_rows(table) -- SELECT COUNT(*) for one explicit table.
  * stream_rows(table, batch_size) -- yield row batches as dicts.
    The connection stays open until the caller has consumed the
    generator, so callers must exhaust it (copy_service does).
  * ping() -- SELECT 1 FROM DUAL, for /health.

The repository takes an explicit SQLAlchemy Table (built by
app/domain/tables.table_for from the checked-in column lists), not a
table name string.  That keeps the repository table-agnostic -- one
repository serves all 49 tables -- while table names themselves still
come only from the catalog.
"""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import func, select, text
from sqlalchemy.engine import Engine

from app.repositories.queries import SELECT_ONE_ORACLE


class OracleRepository:
    """Read access to the Oracle (IDQ) database.  Never writes."""

    def __init__(self, engine_factory) -> None:
        # engine_factory is a callable returning an Engine (e.g. the
        # lru-cached oracle_engine/snowflake_engine functions).  It is
        # NOT called here: constructing a repository must never open a
        # connection or require configuration, so that a dry run or a
        # plain health check can declare the repository as a
        # dependency without touching the database.
        self._engine_factory = engine_factory
        self._engine: Engine | None = None

    @property
    def _engine_resolved(self) -> Engine:
        if self._engine is None:
            self._engine = self._engine_factory()
        return self._engine

    def count_rows(self, table) -> int:
        """Row count for one explicit table."""
        with self._engine_resolved.connect() as conn:
            return int(conn.execute(select(func.count()).select_from(table)).scalar_one())

    def stream_rows(self, table, batch_size: int) -> Iterator[list[dict]]:
        """Yield the table's rows in batches, as plain dicts.

        The connection is held open for the life of the generator.
        Callers must consume it fully; a partially consumed generator
        should be closed (generator.close()) so the connection returns.
        """
        with self._engine_resolved.connect() as conn:
            result = conn.execution_options(stream_results=True).execute(select(table))
            while True:
                batch = result.fetchmany(batch_size)
                if not batch:
                    break
                yield [dict(row._mapping) for row in batch]

    def ping(self) -> None:
        """SELECT 1 FROM DUAL.  Raises on failure."""
        with self._engine_resolved.connect() as conn:
            conn.execute(text(SELECT_ONE_ORACLE))
