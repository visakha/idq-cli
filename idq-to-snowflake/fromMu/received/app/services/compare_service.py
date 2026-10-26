"""Compare service (step C, endpoint 3): IDQ targets vs Snowflake targets.

Pure orchestration, like copy_service: it owns no connection and no
SQL.  Every data operation goes through the SnowflakeRepository it
is given, which is what makes the verdict logic testable with a fake
repository and no database.

Both sides already live in Snowflake by compare time, in the SAME
table in TRS_ETL_WRK: IDQ rows carry DATA_SOURCE='IDQ', Snowflake rows
carry DATA_SOURCE='SNOWFLAKE'.  The entire compare therefore runs
Snowflake-to-Snowflake, filtered by DATA_SOURCE -- no Oracle
round-trip, and no row data leaves Snowflake except counts and key
samples.

For each dimension (one expected table):
  1. Row counts: COUNT(*) WHERE DATA_SOURCE='IDQ' vs
     WHERE DATA_SOURCE='SNOWFLAKE', and the difference
     (snowflake - oracle).  A matching count is necessary, not
     sufficient -- see step 2.
  2. Key set compare: keys in the IDQ side EXCEPT the SNOWFLAKE side
     (oracle-only), and the reverse (snowflake-only), via
     SnowflakeRepository.key_difference.  Matched = distinct keys in
     IDQ minus oracle-only.
  3. Version set compare (only for C_S_* tables): the
     (PKEY_SRC_OBJECT, VERSION_SEQ) set, in both directions.  This
     catches the case a PKEY set matches but a timeline version
     (e.g. a closed relationship row) is missing on one side.
  4. Duplicate note: key sets collapse duplicates by construction.
     If oracle_row_count != matched + oracle_only (or the snowflake
     equivalent), duplicates exist in that table; the message says
     so, because a set compare alone would hide them.  (EXC rows are
     the known case: the same exception can legitimately repeat.)

Spine compare (separate section, not just another dimension):
  * Valid-member spine: distinct INDV_ID in STG_TRS_VALID_MEMBERS,
    IDQ side vs SNOWFLAKE side, in both directions.
  * Party-role spine: distinct PKEY_SRC_OBJECT in C_S_TRS_PTY_RLE,
    IDQ side vs SNOWFLAKE side, in both directions.
  * Coverage per dimension: for each C_S_* dimension table, the
    distinct spine INDV_IDs present in it (first segment of
    PKEY_SRC_OBJECT), IDQ side vs SNOWFLAKE side, via
    SnowflakeRepository.coverage_count.  Reference (TOA catalogue)
    and Exceptions are excluded: their keys are not member spine keys.

Table names come ONLY from app/domain/catalog.py, never from user
input.  User-supplied domain/dimension filters are matched against
the catalog (exact match) in catalog.tables_for_compare, so they
cannot inject SQL.  The sample limit is validated as an integer in
0..200 by the request model.

Verdict:
  * MATCH    -- every compared dimension's counts and key sets match
                (and version sets, where applicable), and both spines match.
  * MISMATCH -- at least one dimension or spine does not match.
  * PARTIAL  -- at least one dimension could not be compared (table
                missing in one schema, or an error on that table);
                the per-dimension message names it.
"""

from __future__ import annotations

from app.core.config import settings
from app.domain import catalog
from app.domain.models import DimensionCompare, SpineCompare
from app.domain.tables import table_for
from app.repositories.snowflake_repository import SnowflakeRepository

SCHEMA = settings.snowflake_schema
IDQ_VALUE = settings.discriminator_idq_value
SNOWFLAKE_VALUE = settings.discriminator_snowflake_value


def _key_sets(repo: SnowflakeRepository, spec, sample_limit: int) -> dict:
    """Matched / oracle-only / snowflake-only key counts + samples.

    Both sides are the same TRS_ETL_WRK table, filtered by DATA_SOURCE.
    """
    table = table_for(spec.name, SCHEMA)
    oracle_only = repo.key_difference(table, table, spec.compare_key, sample_limit, IDQ_VALUE, SNOWFLAKE_VALUE)
    snowflake_only = repo.key_difference(table, table, spec.compare_key, sample_limit, SNOWFLAKE_VALUE, IDQ_VALUE)
    oracle_distinct = repo.distinct_count(table, spec.compare_key, IDQ_VALUE)
    return {
        "matched": oracle_distinct - oracle_only.count,
        "oracle_only_count": oracle_only.count,
        "snowflake_only_count": snowflake_only.count,
        "oracle_only_sample": oracle_only.sample,
        "snowflake_only_sample": snowflake_only.sample,
    }


def _version_sets(repo: SnowflakeRepository, spec) -> dict | None:
    """(PKEY, VERSION_SEQ) set compare, or None if not a C_S_* table."""
    if not spec.name.startswith("C_S_"):
        return None
    table = table_for(spec.name, SCHEMA)
    cols = ["PKEY_SRC_OBJECT", "VERSION_SEQ"]
    oracle_only = repo.key_difference(table, table, cols, 0, IDQ_VALUE, SNOWFLAKE_VALUE)
    snowflake_only = repo.key_difference(table, table, cols, 0, SNOWFLAKE_VALUE, IDQ_VALUE)
    oracle_distinct = repo.distinct_count(table, cols, IDQ_VALUE)
    return {
        "matched": oracle_distinct - oracle_only.count,
        "oracle_only": oracle_only.count,
        "snowflake_only": snowflake_only.count,
    }


def _compare_dimension(repo: SnowflakeRepository, spec, sample_limit: int) -> DimensionCompare:
    table = table_for(spec.name, SCHEMA)
    oracle_count = repo.count_rows(table, discriminator=IDQ_VALUE)
    snowflake_count = repo.count_rows(table, discriminator=SNOWFLAKE_VALUE)
    keys = _key_sets(repo, spec, sample_limit)
    versions = _version_sets(repo, spec)
    messages: list[str] = []
    if oracle_count != keys["matched"] + keys["oracle_only_count"]:
        messages.append(
            "Duplicate compare keys on the IDQ side: row count exceeds "
            "the distinct-key count, so the set compare may hide duplicates. "
            "Check the raw rows for the affected keys."
        )
    if snowflake_count != keys["matched"] + keys["snowflake_only_count"]:
        messages.append(
            "Duplicate compare keys on the Snowflake side: row count exceeds "
            "the distinct-key count. Check the raw rows for the affected keys."
        )
    if spec.name == "EXC_STG_BAD_REC_MEMB":
        messages.append(
            "Exception rows have no unique key: the compare key is a "
            "best-effort tuple (individual + code + attribute + mapping). "
            "Use the per-code count breakdown in the guide's suggested "
            "follow-up (compare by EXCEPTION_CODE) for a second opinion."
        )
    return DimensionCompare(
        domain=spec.domain,
        dimension=spec.dimension,
        table=spec.name,
        compare_key=spec.compare_key,
        oracle_row_count=oracle_count,
        snowflake_row_count=snowflake_count,
        count_diff=snowflake_count - oracle_count,
        matched_keys=keys["matched"],
        oracle_only_keys=keys["oracle_only_count"],
        snowflake_only_keys=keys["snowflake_only_count"],
        oracle_only_sample=keys["oracle_only_sample"],
        snowflake_only_sample=keys["snowflake_only_sample"],
        version_matched_keys=versions["matched"] if versions else None,
        version_oracle_only_keys=versions["oracle_only"] if versions else None,
        version_snowflake_only_keys=versions["snowflake_only"] if versions else None,
        message="; ".join(messages),
    )


def _spine_key_compare(repo: SnowflakeRepository, table_name: str, columns: list[str], label: str, sample_limit: int) -> SpineCompare:
    """One spine: distinct key sets, IDQ side vs SNOWFLAKE side, both directions."""
    table = table_for(table_name, SCHEMA)
    oracle_only = repo.key_difference(table, table, columns, sample_limit, IDQ_VALUE, SNOWFLAKE_VALUE)
    snowflake_only = repo.key_difference(table, table, columns, sample_limit, SNOWFLAKE_VALUE, IDQ_VALUE)
    oracle_keys = repo.distinct_count(table, columns, IDQ_VALUE)
    snowflake_keys = repo.distinct_count(table, columns, SNOWFLAKE_VALUE)
    return SpineCompare(
        spine=label,
        oracle_keys=oracle_keys,
        snowflake_keys=snowflake_keys,
        matched_keys=oracle_keys - oracle_only.count,
        oracle_only_keys=oracle_only.count,
        snowflake_only_keys=snowflake_only.count,
        oracle_only_sample=oracle_only.sample,
        snowflake_only_sample=snowflake_only.sample,
    )


def _spine_section(repo: SnowflakeRepository, sample_limit: int) -> list[SpineCompare]:
    """Valid-member spine, party-role spine, and per-dimension coverage."""
    valid = _spine_key_compare(repo, "STG_TRS_VALID_MEMBERS", ["INDV_ID"], "Valid-member spine (INDV_ID)", sample_limit)
    role = _spine_key_compare(repo, "C_S_TRS_PTY_RLE", ["PKEY_SRC_OBJECT"], "Party-role spine (PKEY_SRC_OBJECT)", sample_limit)

    coverage: list[dict] = []
    for spec in catalog.EXPECTED_TABLES:
        if spec.domain != "Member" or not spec.name.startswith("C_S_TRS_"):
            continue
        if spec.name == "C_S_TRS_PTY_RLE":
            continue  # the spine itself, already reported above
        oracle_cov = repo.coverage_count(table_for(spec.name, SCHEMA), IDQ_VALUE)
        snowflake_cov = repo.coverage_count(table_for(spec.name, SCHEMA), SNOWFLAKE_VALUE)
        coverage.append({
            "dimension": spec.dimension,
            "table": spec.name,
            "oracle_spine_ids": oracle_cov,
            "snowflake_spine_ids": snowflake_cov,
            "diff": snowflake_cov - oracle_cov,
        })
    role.coverage = coverage
    return [valid, role]


def run_compare(
    repo: SnowflakeRepository,
    domains: list[str] | None, dimensions: list[str] | None, sample_limit: int,
) -> tuple[list[DimensionCompare], list[SpineCompare], str]:
    """Compare every requested dimension, plus the spine section.

    Returns (dimensions, spine, verdict).  A dimension that errors
    (e.g. a table missing in TRS_ETL_WRK) is reported with counts of
    -1 and a message, and forces the verdict to PARTIAL -- it is never
    silently skipped.
    """
    specs = catalog.tables_for_compare(domains, dimensions)
    if (domains or dimensions) and not specs:
        raise ValueError(
            "No dimensions match the requested filter. Check the exact "
            "domain/dimension names against GET /config/tables -- a "
            "misspelled filter must not silently report MATCH over zero "
            "dimensions (v3 bug, fixed 3.1)."
        )
    dims: list[DimensionCompare] = []
    for spec in specs:
        try:
            dims.append(_compare_dimension(repo, spec, sample_limit))
        except Exception as exc:
            dims.append(DimensionCompare(
                domain=spec.domain, dimension=spec.dimension, table=spec.name,
                compare_key=spec.compare_key,
                oracle_row_count=-1, snowflake_row_count=-1, count_diff=0,
                matched_keys=0, oracle_only_keys=-1, snowflake_only_keys=-1,
                message=f"Could not compare: {type(exc).__name__}: {exc}. "
                        f"Check that the table exists in {SCHEMA} with both DATA_SOURCE sides.",
            ))
    try:
        spine = _spine_section(repo, sample_limit)
    except Exception as exc:
        spine = [SpineCompare(
            spine="Spine section",
            oracle_keys=-1, snowflake_keys=-1, matched_keys=0,
            oracle_only_keys=-1, snowflake_only_keys=-1,
            coverage=[],
        )]
        if dims:
            dims[0].message = (dims[0].message + f" Spine section failed: {exc}").strip("; ")

    def _dim_matches(d: DimensionCompare) -> bool:
        if d.oracle_row_count < 0:
            return False
        ok = (
            d.count_diff == 0
            and d.oracle_only_keys == 0
            and d.snowflake_only_keys == 0
        )
        if d.version_oracle_only_keys is not None:
            ok = ok and d.version_oracle_only_keys == 0 and d.version_snowflake_only_keys == 0
        return ok

    if any(d.oracle_row_count < 0 for d in dims):
        verdict = "PARTIAL"
    elif all(_dim_matches(d) for d in dims) and all(
        s.oracle_only_keys == 0 and s.snowflake_only_keys == 0 for s in spine if s.oracle_keys >= 0
    ):
        verdict = "MATCH"
    else:
        verdict = "MISMATCH"
    return dims, spine, verdict
