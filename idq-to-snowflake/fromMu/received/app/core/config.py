"""Configuration for the TRS compare API.

Everything is read from environment variables (see .env.example).
Nothing secret is hard-coded.  The API never connects to a database at
import time -- engines are created lazily on first use, so ``uvicorn
app.main:app`` and the test suite can start without Oracle or
Snowflake being reachable.

Snowflake layout:
  * One database per source: MDM_ETL_<SOURCE> (default MDM_ETL_TRS).
    All source-specific tables, views, stored procedures and
    functions for that source live in that database.
  * One schema inside it: <SOURCE>_ETL_WRK (TRS_ETL_WRK for this
    project).  The schema name itself carries the source, so a
    bare `TRS_ETL_WRK.C_S_TRS_PTY` reference is unambiguous
    without its database: TRS, not ECI, WIC, or any other source.
    The fully qualified form is
    MDM_ETL_TRS.TRS_ETL_WRK.C_S_TRS_PTY.  The duplication of the
    source in database and schema is intentional, not a typo:
    the database is the namespace, the schema is the
    self-describing name a reader, a log line, or a copied
    query actually sees.
  * One table per target, both sides in it, told apart by a
    discriminator (pivotal) column: DATA_SOURCE = 'IDQ' for rows
    IDQ produced, 'SNOWFLAKE' for rows the Snowflake ETL produced.
    The compare filters on DATA_SOURCE; it never compares two
    schemas.  Input tables are the shared Oracle input, copied once,
    and carry no discriminator -- they are not IDQ-vs-Snowflake
    data (see the guide, §2, for the reasoning, and for what
    "source tables" means in the discriminator sentence).
  * COMMON (framework, not a copy destination): database
    MDM_ETL_COMMON, schema COMMON, holding Job Controls, Metrics,
    and reusable Functions / Stored Procedures (date parsing,
    birth-date validation, etc.) shared across all sources.  The
    compare API does not copy into COMMON and does not read it;
    the ETL procedures write their checkpoints there and call its
    functions qualified.  COMMON's exact database is flagged in
    the guide as the one layout detail still to confirm with the
    site, because it was not spelled out in the correction --
    override it with SNOWFLAKE_COMMON_DATABASE /
    SNOWFLAKE_COMMON_SCHEMA if it differs.

Schema and database names are derived from SNOWFLAKE_SOURCE
unless set explicitly (SNOWFLAKE_SCHEMA, SNOWFLAKE_DATABASE).
"""

from __future__ import annotations

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All settings.  Defaults are for local development only."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # -- API itself -------------------------------------------------------
    api_key: str | None = None  # if set, clients must send X-API-Key
    control_db_url: str = "sqlite:///./trs_compare.db"

    # -- Oracle (IDQ side) ------------------------------------------------
    # Three Oracle schemas are involved (STAGING, HHS_MDM, RDM); they
    # live in one Oracle database, reached with one user that has SELECT
    # on all of them.  Oracle layer (LANDING / STAGING / HHS_MDM) does
    # NOT determine Snowflake destination; the source database and
    # its <SOURCE>_ETL_WRK schema do (see above).
    oracle_host: str = "localhost"
    oracle_port: int = 1521
    oracle_service: str = "ORCL"
    oracle_user: str = ""
    oracle_password: str = ""

    # -- Snowflake (comparison side) --------------------------------------
    # SSO: see the guide, "Authentication".  In short:
    #   * Local, interactive use:  SNOWFLAKE_AUTHENTICATOR=externalbrowser
    #     (a browser window opens for your SSO login; unsuitable for an
    #     unattended server).
    #   * API server use:           SNOWFLAKE_AUTHENTICATOR=oauth and
    #     SNOWFLAKE_OAUTH_TOKEN=<token from your IdP>, or
    #     SNOWFLAKE_AUTHENTICATOR=snowflake with a service user.
    # The API never prints or logs the token.
    snowflake_account: str = ""
    snowflake_user: str = ""
    snowflake_password: str | None = None
    snowflake_authenticator: str = "snowflake"
    snowflake_oauth_token: str | None = None
    # Source for this API instance.  Drives the database and schema
    # defaults below.  One instance serves one source, because the
    # catalog is source-specific; future sources (ECI, WIC, TTF, CRE,
    # FSS) are new instances with SNOWFLAKE_SOURCE=<that source>
    # and their own catalog, sharing MDM_ETL_COMMON.  For ECI, the
    # derived names are database MDM_ETL_ECI, schema ECI_ETL_WRK.
    snowflake_source: str = "TRS"
    # Database: None means "derive from snowflake_source".
    snowflake_database: str | None = None
    # Schema: None means "derive from snowflake_source" as
    # <SOURCE>_ETL_WRK.
    snowflake_schema: str | None = None
    # COMMON framework database/schema (see module docstring).
    snowflake_common_database: str | None = None
    snowflake_common_schema: str = "COMMON"
    snowflake_warehouse: str = ""
    snowflake_role: str = ""

    # -- SQLite harness (testing only, never production) ------------------
    # File path for the persistent SQLite harness database (see
    # tests/sqlite_harness.py and GET /sqlite/tables).  When set,
    # the inspection endpoint reads ONLY this file -- it never
    # takes a path from a request, so a caller cannot point it
    # at an arbitrary file.  When empty, /sqlite/tables answers
    # 404 ("not configured") instead of inventing a database.
    # The file is the TRS_ETL_WRK database itself: when the
    # harness ATTACHes it, its tables appear as
    # TRS_ETL_WRK.<table>; opened directly, they appear as
    # <table>.  Same file, same rows, both views.
    sqlite_harness_db_path: str | None = None

    # -- Discriminator (pivotal) column -----------------------------------
    # Added to every TARGET (expected) table in TRS_ETL_WRK.  The copy
    # writes 'IDQ'; the Snowflake ETL writes 'SNOWFLAKE' (the DDL
    # defaults the column to 'SNOWFLAKE', so existing procedures
    # that do not name it still produce the correct value -- see
    # the guide).  Input tables have no discriminator column.
    discriminator_column: str = "DATA_SOURCE"
    discriminator_idq_value: str = "IDQ"
    discriminator_snowflake_value: str = "SNOWFLAKE"

    @model_validator(mode="after")
    def _derive_database_names(self):
        source = (self.snowflake_source or "TRS").upper()
        if self.snowflake_database is None:
            self.snowflake_database = f"MDM_ETL_{source}"
        if self.snowflake_schema is None:
            self.snowflake_schema = f"{source}_ETL_WRK"
        if self.snowflake_common_database is None:
            self.snowflake_common_database = "MDM_ETL_COMMON"
        return self

    # -- Copy / compare behaviour -----------------------------------------
    copy_batch_size: int = 5000
    compare_sample_limit: int = 20


settings = Settings()
