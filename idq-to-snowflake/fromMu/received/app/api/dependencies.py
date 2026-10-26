"""Dependency providers: how FastAPI builds the repositories.

This is the Python equivalent of Spring's @Bean / constructor
injection, without a container: plain functions that construct a
repository from a lazily created engine.  Routes declare the
repository they need with Depends(get_..._repository), and tests
replace a provider with app.dependency_overrides to inject a fake
or a temp-database repository -- no monkeypatching of globals.

Engines are cached (see core/db.py) and, more importantly, lazy:
repositories receive the engine factory, not an engine, and only
call it on first use.  Constructing a repository per request is
therefore cheap and configuration-free: the repository object is
new, the engine and its connection pool are shared, and a dry run
that never uses a repository never touches its database.
"""

from __future__ import annotations

from app.core.db import control_engine, oracle_engine, snowflake_engine
from app.repositories.oracle_repository import OracleRepository
from app.repositories.run_repository import RunRepository
from app.repositories.snowflake_repository import SnowflakeRepository


def get_run_repository() -> RunRepository:
    """Job history repository (SQLite by default)."""
    return RunRepository(control_engine())


def get_oracle_repository() -> OracleRepository:
    """Read-only Oracle repository."""
    return OracleRepository(oracle_engine)


def get_snowflake_repository() -> SnowflakeRepository:
    """Snowflake comparison-schemas repository."""
    return SnowflakeRepository(snowflake_engine)
