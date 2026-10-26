"""Snowflake repository: the comparison side (v5: one database
MDM_ETL_<SOURCE>, one schema TRS_ETL_WRK, discriminator DATA_SOURCE).

Same pattern as OracleRepository: explicit, typed methods for the
operations the job needs, no derived queries, no generic CRUD, no
ORM.  The repository owns connection handling and the Core
statements; services own the business rules (which tables to copy
where, what a verdict means) and never touch a connection.

Methods, grouped by job:
  Copy:   truncate(schema, table_name), insert_rows(table, rows),
          count_rows(table, discriminator=None)
  Compare: key_difference(left, right, columns, sample_limit,
              left_discriminator, right_discriminator),
          distinct_count(table, columns, discriminator),
          coverage_count(table, discriminator)
  ETL:    use_schema(schema), call_procedure(procedure),
          delete_discriminator_rows(table, discriminator)
  Health: ping()

key_difference is the compare's core operation, and it is a Core
statement, not a string: select(key columns) EXCEPT select(key
columns), in both directions, with samples taken from the same
statement.  Comparing the key columns directly (rather than joining
them into a string) is what makes NULL handling correct: set
operations treat NULLs as equal to each other, with no placeholder
and no separator to collide.

The only text() in this file is for TRUNCATE / USE SCHEMA / CALL,
which have no Core equivalent.  Their arguments come from the named
constants in queries.py, filled with schema/table/procedure names
that the services supply from the catalog / workflow allowlists --
never from a request body.  If you add a method that takes a name
from anywhere else, validate it against the allowlist first.
"""

from __future__ import annotations

from sqlalchemy import case, func, literal, select, text
from sqlalchemy.engine import Engine

from app.domain.models import KeyDifference
from app.repositories.queries import (
    CALL_PROCEDURE,
    SELECT_ONE_SNOWFLAKE,
    TRUNCATE_TABLE,
    USE_SCHEMA,
)


class SnowflakeRepository:
    """Read/write access to the Snowflake comparison schemas."""

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

    # -- Copy --------------------------------------------------------------
    def truncate(self, schema: str, table_name: str) -> None:
        """TRUNCATE TABLE, via the named constant in queries.py."""
        with self._engine_resolved.begin() as conn:
            conn.execute(text(TRUNCATE_TABLE.format(schema=schema, table=table_name)))

    def insert_rows(self, table, rows: list[dict]) -> None:
        """Insert one batch of rows (executemany), in one transaction."""
        if not rows:
            return
        with self._engine_resolved.begin() as conn:
            conn.execute(table.insert(), rows)

    def count_rows(self, table, discriminator: str | None = None) -> int:
        """Row count for one explicit table, optionally one DATA_SOURCE side.

        discriminator=None counts the whole table (inputs, which have
        no discriminator column).  For target tables, pass 'IDQ' or
        'SNOWFLAKE' -- counting the whole table would mix both sides.
        """
        stmt = select(func.count()).select_from(table)
        if discriminator is not None:
            stmt = stmt.where(table.c.DATA_SOURCE == discriminator)
        with self._engine_resolved.connect() as conn:
            return int(conn.execute(stmt).scalar_one())

    # -- Compare -------------------------------------------------------------
    def distinct_count(self, table, columns: list[str], discriminator: str | None = None) -> int:
        """COUNT(DISTINCT key) via a distinct subquery (composite-safe).

        discriminator filters to one DATA_SOURCE side when given.
        """
        stmt = select(*[table.c[col] for col in columns])
        if discriminator is not None:
            stmt = stmt.where(table.c.DATA_SOURCE == discriminator)
        distinct = stmt.distinct().subquery()
        with self._engine_resolved.connect() as conn:
            return int(conn.execute(select(func.count()).select_from(distinct)).scalar_one())

    def key_difference(
        self, left_table, right_table, columns: list[str], sample_limit: int,
        left_discriminator: str | None = None, right_discriminator: str | None = None,
    ) -> KeyDifference:
        """Keys in left EXCEPT right: (count, pipe-joined samples).

        In v5 left and right are usually the SAME table in TRS_ETL_WRK,
        told apart by left_discriminator / right_discriminator
        ('IDQ' vs 'SNOWFLAKE').  The samples are joined in Python
        for display only; the comparison itself is on the raw
        columns, so no separator or placeholder can collapse two
        different keys into one.
        """
        left_stmt = select(*[left_table.c[col] for col in columns])
        if left_discriminator is not None:
            left_stmt = left_stmt.where(left_table.c.DATA_SOURCE == left_discriminator)
        right_stmt = select(*[right_table.c[col] for col in columns])
        if right_discriminator is not None:
            right_stmt = right_stmt.where(right_table.c.DATA_SOURCE == right_discriminator)
        difference = left_stmt.except_(right_stmt)
        sub = difference.subquery()
        with self._engine_resolved.connect() as conn:
            count = int(conn.execute(select(func.count()).select_from(sub)).scalar_one())
            sample_rows = conn.execute(difference.limit(sample_limit)).all() if sample_limit else []
        sample = ["|".join("" if v is None else str(v) for v in row) for row in sample_rows]
        return KeyDifference(count=count, sample=sample)

    def coverage_count(self, table, discriminator: str | None = None) -> int:
        """Distinct spine ids in a dimension table, for one DATA_SOURCE side.

        A dimension's spine id is the first pipe-separated segment of
        its PKEY_SRC_OBJECT (for Member parties, the INDV_ID).

        The expression is dialect-aware, and deliberately so: on
        Snowflake it is SPLIT_PART(PKEY, '|', 1); on SQLite (the
        test harness in tests/sqlite_harness.py -- there is no
        SPLIT_PART there) it is the equivalent SUBSTR/INSTR
        expression.  Same semantics, same result; the Snowflake
        path is unchanged, and this is the ONLY Snowflake-only
        function the compare uses -- every other compare statement
        is plain SQLAlchemy Core and already runs on SQLite.
        """
        if self._engine_resolved.dialect.name == "sqlite":
            pipe_pos = func.instr(table.c.PKEY_SRC_OBJECT, literal("|"))
            spine_id = case(
                (pipe_pos > 0, func.substr(table.c.PKEY_SRC_OBJECT, 1, pipe_pos - 1)),
                else_=table.c.PKEY_SRC_OBJECT,
            )
        else:
            spine_id = func.split_part(table.c.PKEY_SRC_OBJECT, literal("|"), literal(1))
        stmt = select(func.count(func.distinct(spine_id))).select_from(table)
        if discriminator is not None:
            stmt = stmt.where(table.c.DATA_SOURCE == discriminator)
        with self._engine_resolved.connect() as conn:
            return int(conn.execute(stmt).scalar_one())

    # -- ETL -----------------------------------------------------------------
    # There is deliberately no standalone use_schema() method: USE
    # SCHEMA only affects its own session, so setting it on a
    # throwaway connection and then calling a procedure on another
    # connection would silently do nothing.  The methods below keep
    # USE SCHEMA and the statements that depend on it on one
    # connection, where the schema actually applies.
    def call_procedure_in_schema(self, schema: str, procedure: str) -> str:
        """USE SCHEMA, then CALL procedure, on one connection.

        Returns the procedure's return value as text (first row,
        first column), or "" if it returned no row.  The procedure
        name must come from the workflow allowlist in etl_service.py.
        """
        with self._engine_resolved.connect() as conn:
            conn.execute(text(USE_SCHEMA.format(schema=schema)))
            row = conn.execute(text(CALL_PROCEDURE.format(procedure=procedure))).fetchone()
            return str(row[0]) if row is not None else ""

    def delete_discriminator_rows(self, table, discriminator: str) -> None:
        """DELETE one DATA_SOURCE side from a target table (ETL clear step).

        This is a DELETE, not a TRUNCATE, on purpose: TRUNCATE would
        also delete the IDQ rows that must be preserved for the
        compare.  Deleting only DATA_SOURCE='SNOWFLAKE' leaves the
        IDQ side untouched, and makes a re-run of the ETL (without a
        fresh copy) safe against the insert-only guards.
        """
        with self._engine_resolved.begin() as conn:
            conn.execute(table.delete().where(table.c.DATA_SOURCE == discriminator))

    # -- Health ---------------------------------------------------------------
    def ping(self) -> None:
        """SELECT 1.  Raises on failure."""
        with self._engine_resolved.connect() as conn:
            conn.execute(text(SELECT_ONE_SNOWFLAKE))
