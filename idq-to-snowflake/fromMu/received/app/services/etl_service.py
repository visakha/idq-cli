"""ETL service (step C, endpoint 2): run the Snowflake ETL in TRS_ETL_WRK.

Pure orchestration, like the other services: it owns no connection
and no SQL.  All database work goes through the SnowflakeRepository
it is given (truncate in schema, call procedure in schema); this
service owns only workflow order, failure handling, and parsing the
runners' return values.

The Snowflake procedures are the simplified modular rewrite (no
step-level resume): each procedure cleans its own WRK_TRS_* tables at
its start, runs every step fresh, publishes in one transaction, and
leaves its work tables in place until the next run.  This service
therefore does NOT implement resume, skip, or cleanup logic of its
own -- it just calls the workflow runners, in order, and records what
they returned.

Order: TOA catalogue first, then Ongoing.  The Ongoing workflow's
role-TOA mapping reads STG_TRS_D_LU_TOA (a source table), not
C_S_LU_TOA, so the order is not a hard dependency -- but running the
reference catalogue first is the logical order, and it matches the
IDQ taskflow order (TOA workflow, then Ongoing workflow).

The runners are installed in TRS_ETL_WRK in the source database
(MDM_ETL_TRS for this project; they must be created there, with the
mapping procedures, before the first ETL run -- see the guide,
"Installing the Snowflake ETL in TRS_ETL_WRK").  Because the procedures
use unqualified table names, they resolve to TRS_ETL_WRK when called
with that schema as the session schema -- the repository therefore
issues USE SCHEMA TRS_ETL_WRK on the same connection before each CALL,
and never passes a schema-qualified procedure name.

Before any runner is called, this service deletes the SNOWFLAKE
side (DATA_SOURCE='SNOWFLAKE') from every target table in TRS_ETL_WRK.
It is a DELETE by discriminator, never a TRUNCATE, so the IDQ side
is preserved.  This is the v5 form of the old "WORK must start
empty" rule: without it, the procedures' insert-only guards would
suppress the new Snowflake rows on a re-run.  A fresh copy already
truncated the target tables, so this delete is normally a no-op --
it is here so that an ETL re-run without a fresh copy is still
correct.

Return value parsing: each runner returns a string starting with
"JOB_RUN_ID=...".  That id is the Snowflake workflow run id (the
P_JOB_RUN_ID the user asked to keep for workflow-level grouping) and
is returned to the caller so the Snowflake control table
(JOB_CONTROL_ETL in COMMON, with SOURCE='TRS') can be queried for
the step story.
"""

from __future__ import annotations

import re

from app.core.config import settings
from app.repositories.snowflake_repository import SnowflakeRepository

# Workflow runners, in the order they are called by default.
# Keys are the request's workflow names; values are procedure names.
# This is the allowlist for CALL: a procedure name reaches the
# repository only from here, never from a request body.
WORKFLOW_PROCEDURES: dict[str, str] = {
    "toa": "sp_etl_run_wf_TRS_Stage_Load_TOA",
    "ongoing": "sp_etl_run_wf_TRS_Stage_Load_1_Ongoing",
}

_JOB_RUN_ID_RE = re.compile(r"JOB_RUN_ID=([^\s]+)")


def _parse_job_run_id(return_text: str | None) -> str | None:
    if not return_text:
        return None
    match = _JOB_RUN_ID_RE.search(return_text)
    return match.group(1) if match else None


def run_etl(
    repo: SnowflakeRepository, workflows: list[str],
) -> tuple[list[dict[str, str]], str, str | None]:
    """Call the requested workflow runners in order.

    Returns (per-workflow results, overall status, snowflake job run id
    of the last workflow run).  A failure in one workflow stops the
    run: later workflows are not started, because Ongoing depends on
    the spine and reference data the earlier workflow produces.  The
    per-workflow list records which workflows ran and which were not
    reached.
    """
    from app.domain import catalog  # local import to avoid a cycle at module load

    if not workflows:
        raise ValueError(
            "At least one workflow is required. An empty workflow list "
            "must not silently report COMPLETED over zero work "
            "(v3 bug, fixed 3.1)."
        )
    for name in workflows:
        if name not in WORKFLOW_PROCEDURES:
            raise ValueError(
                f"Unknown workflow: {name!r}. Allowed: {sorted(WORKFLOW_PROCEDURES)}"
            )

    results: list[dict[str, str]] = []
    last_job_run_id: str | None = None
    work_schema = settings.snowflake_schema

    # Always clear the SNOWFLAKE side first (see module docstring).
    # IDQ rows are preserved by construction: this is a DELETE by
    # discriminator, not a TRUNCATE.
    from app.domain.tables import table_for

    for spec in catalog.EXPECTED_TABLES:
        repo.delete_discriminator_rows(
            table_for(spec.name, work_schema), settings.discriminator_snowflake_value
        )
    results.append({
        "workflow": "(clear-snowflake)",
        "status": "CLEARED",
        "message": (
            f"Deleted DATA_SOURCE='SNOWFLAKE' rows from "
            f"{len(catalog.EXPECTED_TABLES)} target tables in {work_schema} "
            f"(IDQ rows preserved) before running the procedures."
        ),
    })

    for name in workflows:
        proc = WORKFLOW_PROCEDURES[name]
        try:
            return_text = repo.call_procedure_in_schema(work_schema, proc)
            job_run_id = _parse_job_run_id(return_text)
            if job_run_id:
                last_job_run_id = job_run_id
            results.append({
                "workflow": name,
                "procedure": proc,
                "status": "COMPLETED",
                "snowflake_job_run_id": job_run_id or "",
                "message": return_text,
            })
        except Exception as exc:
            results.append({
                "workflow": name,
                "procedure": proc,
                "status": "FAILED",
                "message": f"{type(exc).__name__}: {exc}",
            })
            # Stop here; do not start later workflows on a failed one.
            remaining = [w for w in workflows[workflows.index(name) + 1:]]
            for w in remaining:
                results.append({
                    "workflow": w,
                    "procedure": WORKFLOW_PROCEDURES[w],
                    "status": "NOT_RUN",
                    "message": "Not started because an earlier workflow failed.",
                })
            return results, "FAILED", last_job_run_id
    return results, "COMPLETED", last_job_run_id
