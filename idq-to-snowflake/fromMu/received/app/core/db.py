"""Database connections: Oracle, Snowflake, and the local control store.

All engines are created lazily (first use) and cached, so importing
this module never opens a connection.  That is what makes the test
suite and ``/health`` (without db checks) work with no databases at all.

No ORM, no reflection, anywhere in this module:
  * Engines are plain SQLAlchemy engines.  No ORM Session, no
    declarative models, no automap, no MetaData.reflect().
  * Table shapes come from app/domain/tables.py -- explicit column
    lists generated once from the Oracle DDL and checked in as code.
    The running API never asks a database what columns a table has.
  * Snowflake DDL for the comparison schemas is NOT executed by this
    API.  Apply sql/01_*.sql .. sql/04_*.sql once, by hand (step A),
    before the first copy run.  The API only TRUNCATEs, INSERTs,
    SELECTs and CALLs procedures in schemas you have already created.
"""

from __future__ import annotations

from functools import lru_cache

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine

from app.core.config import settings


@lru_cache(maxsize=1)
def control_engine() -> Engine:
    """Engine for the local control store (SQLite by default).

    The runs table itself is created by RunRepository on construction
    (CREATE TABLE IF NOT EXISTS), not here, so this function stays
    a pure engine factory.
    """
    return create_engine(settings.control_db_url, echo=False)


@lru_cache(maxsize=1)
def oracle_engine() -> Engine:
    """Oracle engine via oracledb (thin mode: no Oracle client needed).

    Requires: pip install oracledb
    DSN form: host:port/service_name
    """
    if not settings.oracle_user:
        raise RuntimeError(
            "Oracle is not configured: set ORACLE_USER / ORACLE_PASSWORD "
            "(and ORACLE_HOST / ORACLE_PORT / ORACLE_SERVICE) in .env"
        )
    dsn = f"{settings.oracle_host}:{settings.oracle_port}/{settings.oracle_service}"
    return create_engine(f"oracle+oracledb://{settings.oracle_user}:{settings.oracle_password}@{dsn}")


@lru_cache(maxsize=1)
def snowflake_engine() -> Engine:
    """Snowflake engine via snowflake-sqlalchemy.

    Requires: pip install snowflake-sqlalchemy snowflake-connector-python
    Authentication (see config.py and the guide):
      * authenticator=snowflake  -> user + password
      * authenticator=oauth      -> SNOWFLAKE_OAUTH_TOKEN (SSO token
        from your IdP; the API never logs it)
      * authenticator=externalbrowser -> interactive SSO browser flow;
        local development only, not for an unattended server.
    """
    if not settings.snowflake_account or not settings.snowflake_user:
        raise RuntimeError(
            "Snowflake is not configured: set SNOWFLAKE_ACCOUNT and "
            "SNOWFLAKE_USER (plus authenticator/token or password) in .env"
        )
    url = (
        f"snowflake://{settings.snowflake_user}"
        f"@{settings.snowflake_account}/{settings.snowflake_database}"
    )
    connect_args: dict[str, str] = {}
    if settings.snowflake_authenticator:
        connect_args["authenticator"] = settings.snowflake_authenticator
    if settings.snowflake_oauth_token:
        connect_args["token"] = settings.snowflake_oauth_token
    if settings.snowflake_password:
        connect_args["password"] = settings.snowflake_password
    if settings.snowflake_warehouse:
        connect_args["warehouse"] = settings.snowflake_warehouse
    if settings.snowflake_role:
        connect_args["role"] = settings.snowflake_role
    return create_engine(url, connect_args=connect_args)


def snowflake_schema_for(spec_name: str, copy_role: str) -> list[str]:
    """Snowflake destination schema for one catalog table (v5).

    There is exactly one: TRS_ETL_WRK, in the source database
    (MDM_ETL_<SOURCE>).  Inputs and expected tables alike go there;
    expected tables are told apart from Snowflake-produced rows
    inside the table by the DATA_SOURCE discriminator, not by a
    schema.  COMMON is framework-only (job control, metrics,
    shared functions) and is never a copy destination.
    """
    return [settings.snowflake_schema]
