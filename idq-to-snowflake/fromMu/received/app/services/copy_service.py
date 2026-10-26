"""Copy service (step C, endpoint 1): Oracle -> Snowflake (v5).

This service is pure orchestration.  It owns no connection, no SQL
and no engine: every data operation goes through the repositories
it is given (OracleRepository, SnowflakeRepository), which is what
makes it testable with fake repositories and no database.  The
service owns only the business rules:

  * Catalog order: inputs first, then expected tables.
  * Everything goes to one schema: TRS_ETL_WRK, in the source database
    (MDM_ETL_TRS for this project).  There is no SRC / IDQ / WORK
    schema split in v5.
  * Input tables: TRUNCATE, then load the Oracle rows as-is.  No
    discriminator column: input rows are the shared Oracle input.
  * Expected (target) tables: TRUNCATE the whole table (both
    DATA_SOURCE sides -- the previous day's IDQ and SNOWFLAKE rows
    are both stale), then load the Oracle rows with
    DATA_SOURCE='IDQ' added to every row.  The SNOWFLAKE side is
    then empty until the ETL step fills it.  Never load IDQ rows
    without the discriminator, and never pre-load SNOWFLAKE rows:
    the Snowflake procedures are insert-only with existing-key
    guards, so pre-loaded SNOWFLAKE rows would suppress the rows
    the ETL is supposed to produce.
  * After every copy, the row count on the relevant side must equal
    the Oracle row count, or that table is FAILED (recorded, not hidden).
  * Missing tables (the four objects not in the supplied exports)
    are SKIPPED, not failed: the run ends PARTIAL, naming them.

This service does no DDL: TRS_ETL_WRK and its tables must already exist
(step A).  TRUNCATE is used instead of DROP/CREATE so the DDL -- and
any grants on it -- survives every copy run.
"""

from __future__ import annotations

from app.core.config import settings
from app.core.db import snowflake_schema_for
from app.domain import catalog
from app.domain.models import TableCopyResult
from app.domain.tables import table_for
from app.repositories.oracle_repository import OracleRepository
from app.repositories.snowflake_repository import SnowflakeRepository

SCHEMA = settings.snowflake_schema
IDQ_VALUE = settings.discriminator_idq_value
DISC_COL = settings.discriminator_column


def _copy_table(
    oracle: OracleRepository, snowflake: SnowflakeRepository,
    spec, batch_size: int,
) -> int:
    """Stream one Oracle table into TRS_ETL_WRK.  Returns rows copied.

    For expected tables, DATA_SOURCE='IDQ' is added to every row.
    For input tables, rows are loaded as-is.
    """
    oracle_table = table_for(spec.name, spec.oracle_schema or "")
    snowflake_table = table_for(spec.name, SCHEMA)
    snowflake.truncate(SCHEMA, spec.name)
    copied = 0
    for batch in oracle.stream_rows(oracle_table, batch_size):
        if spec.copy_role == "expected":
            batch = [{**row, DISC_COL: IDQ_VALUE} for row in batch]
        snowflake.insert_rows(snowflake_table, batch)
        copied += len(batch)
    return copied


def run_copy(
    oracle: OracleRepository,
    snowflake: SnowflakeRepository,
    requested_tables: list[str] | None,
    batch_size: int = settings.copy_batch_size,
) -> tuple[list[TableCopyResult], str]:
    """Run the whole copy.  Returns (per-table results, overall status).

    Overall status: COMPLETED (all copied), PARTIAL (at least one
    table skipped as missing, or a table failed but the run
    continued -- see the per-table statuses), FAILED (nothing copied).
    A database-connection failure is raised to the caller, not
    returned here, because it means no table could even be attempted.
    """
    specs = catalog.tables_for_copy(requested_tables)
    results: list[TableCopyResult] = []
    for spec in specs:
        if spec.missing_from_exports:
            results.append(TableCopyResult(
                table=spec.name, oracle_schema=spec.oracle_schema,
                copy_role=spec.copy_role, status="SKIPPED_MISSING",
                destinations=[],
                message="Not in the supplied Oracle exports; definition "
                        "must be supplied first (sql/04_missing_tables.sql). "
                        "This table was NOT copied.",
            ))
            continue
        try:
            oracle_rows = oracle.count_rows(table_for(spec.name, spec.oracle_schema or ""))
            destinations = snowflake_schema_for(spec.name, spec.copy_role)
            _copy_table(oracle, snowflake, spec, batch_size)
            snowflake_table = table_for(spec.name, SCHEMA)
            if spec.copy_role == "expected":
                snowflake_rows = snowflake.count_rows(snowflake_table, discriminator=IDQ_VALUE)
            else:
                snowflake_rows = snowflake.count_rows(snowflake_table)
            status = "COPIED" if snowflake_rows == oracle_rows else "FAILED"
            if spec.copy_role == "expected":
                message = (
                    f"Copied {oracle_rows} rows to {SCHEMA} with {DISC_COL}='IDQ'; "
                    f"SNOWFLAKE side is empty until the ETL step fills it."
                    if status == "COPIED" else
                    f"Row-count mismatch after copy to {SCHEMA} (IDQ side): "
                    f"Oracle={oracle_rows}, Snowflake={snowflake_rows}. Investigate before ETL."
                )
            else:
                message = (
                    f"Copied {oracle_rows} rows to {SCHEMA}."
                    if status == "COPIED" else
                    f"Row-count mismatch after copy: Oracle={oracle_rows}, "
                    f"Snowflake={snowflake_rows}. Investigate before ETL."
                )
            results.append(TableCopyResult(
                table=spec.name, oracle_schema=spec.oracle_schema,
                copy_role=spec.copy_role, status=status,
                oracle_row_count=oracle_rows, snowflake_row_count=snowflake_rows,
                destinations=destinations, message=message,
            ))
        except Exception as exc:  # per-table failure must not hide the rest
            results.append(TableCopyResult(
                table=spec.name, oracle_schema=spec.oracle_schema,
                copy_role=spec.copy_role, status="FAILED",
                destinations=[],
                message=f"{type(exc).__name__}: {exc}",
            ))
    statuses = {r.status for r in results}
    if statuses <= {"COPIED", "RESET_EMPTY"}:
        overall = "COMPLETED"
    elif "FAILED" in statuses and "COPIED" not in statuses:
        overall = "FAILED"
    else:
        overall = "PARTIAL"
    return results, overall
