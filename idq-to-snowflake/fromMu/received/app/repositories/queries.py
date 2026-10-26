"""Named SQL constants -- the Spring Data JDBC `sql-named-queries`
idea, translated pythonically.

What this file is, and is not:
  * It holds the handful of statements that are genuinely fixed and
    have no SQLAlchemy Core equivalent: TRUNCATE, USE SCHEMA, CALL,
    and the health-check SELECTs.  Everything else in this project
    (counts, inserts, EXCEPT key sets, spine coverage) is a Core
    statement built in the repositories, not a string here.
  * It is NOT a properties file looked up by string key at runtime.
    These are module-level constants imported by name, so a typo is
    an ImportError at startup and "find usages" works.  That is the
    deliberate difference from `Customer.findByEmail` in a
    `.properties` file, where a renamed method or a mistyped key
    fails only when that query runs.
  * The `{schema}`, `{table}` and `{procedure}` placeholders in the
    templates are NEVER filled from user input.  They are filled only
    with names from app/domain/catalog.py (the allowlist) or from the
    workflow-procedure allowlist in etl_service.py.  A repository
    method that receives a schema/table/procedure from anywhere else
    must validate it against those allowlists first -- see
    snowflake_repository.py.

If a statement needs to change, change it here, once, and every
repository method that uses it changes with it.  Do not copy a
statement into a service or a route.
"""

from __future__ import annotations

# --- Fixed statements ------------------------------------------------------
# TRUNCATE has no Core equivalent.  Template only: the caller supplies
# schema/table from the catalog allowlist, never from a request body.
TRUNCATE_TABLE = "TRUNCATE TABLE {schema}.{table}"

# Snowflake session schema for the ETL runners.  The procedures use
# unqualified table names, so they resolve to MDM_ETL_TRS_WORK only when this
# has been issued first.  Template only: schema from settings, which
# is deployment configuration, not user input.
USE_SCHEMA = "USE SCHEMA {schema}"

# Call a workflow runner procedure.  Template only: procedure from the
# WORKFLOW_PROCEDURES allowlist in etl_service.py, never from a request.
CALL_PROCEDURE = "CALL {procedure}()"

# Health checks (see api/routes.py).  These are the only SELECTs in
# this file, because they are the only ones that are fixed strings
# rather than Core statements over explicit tables.
SELECT_ONE_ORACLE = "SELECT 1 FROM DUAL"
SELECT_ONE_SNOWFLAKE = "SELECT 1"
SELECT_ONE_CONTROL = "SELECT 1"
