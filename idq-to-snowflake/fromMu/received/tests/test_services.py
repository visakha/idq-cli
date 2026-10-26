"""Service tests with fake repositories: no database at all.

This is the test v2 could not write: services take repositories as
arguments, so a fake repository (plain Python objects, same method
names) is enough to exercise copy orchestration, compare verdicts,
and ETL failure handling.  No Oracle, no Snowflake, no SQLite.
"""

from app.core.config import settings
from app.domain.models import KeyDifference
from app.services import compare_service, copy_service, etl_service

SCHEMA = settings.snowflake_schema
IDQ_VALUE = settings.discriminator_idq_value
SNOWFLAKE_VALUE = settings.discriminator_snowflake_value


class FakeOracle:
    """Oracle data as plain dicts, keyed by table name."""

    def __init__(self, rows_by_table: dict):
        self.rows_by_table = rows_by_table

    def count_rows(self, table) -> int:
        return len(self.rows_by_table.get(table.name, []))

    def stream_rows(self, table, batch_size: int):
        rows = self.rows_by_table.get(table.name, [])
        yield list(rows)


class FakeSnowflake:
    """Snowflake data as plain dicts, keyed by (schema, table name)."""

    def __init__(self, rows_by_schema_table: dict | None = None):
        self.store: dict = dict(rows_by_schema_table or {})
        self.truncated: list = []
        self.called_procedures: list = []
        self.raise_on_count: set = set()

    # -- Copy ------------------------------------------------------------
    def truncate(self, schema: str, table_name: str) -> None:
        self.store[(schema, table_name)] = []
        self.truncated.append((schema, table_name))

    def insert_rows(self, table, rows: list[dict]) -> None:
        self.store.setdefault((table.schema, table.name), []).extend(rows)

    def count_rows(self, table, discriminator: str | None = None) -> int:
        if (table.schema, table.name) in self.raise_on_count:
            raise RuntimeError("table missing")
        return len(self._rows(table, discriminator))

    # -- Compare -----------------------------------------------------------
    def _rows(self, table, discriminator=None):
        rows = self.store.get((table.schema, table.name), [])
        if discriminator is not None:
            rows = [r for r in rows if r.get("DATA_SOURCE") == discriminator]
        return rows

    def distinct_count(self, table, columns: list[str], discriminator: str | None = None) -> int:
        rows = self._rows(table, discriminator)
        return len({tuple(row[c] for c in columns) for row in rows})

    def key_difference(self, left_table, right_table, columns: list[str], sample_limit: int, left_discriminator=None, right_discriminator=None) -> KeyDifference:
        left = {tuple(row[c] for c in columns) for row in self._rows(left_table, left_discriminator)}
        right = {tuple(row[c] for c in columns) for row in self._rows(right_table, right_discriminator)}
        diff = sorted(left - right, key=str)
        sample = ["|".join("" if v is None else str(v) for v in key) for key in diff[:sample_limit]] if sample_limit else []
        return KeyDifference(count=len(diff), sample=sample)

    def coverage_count(self, table, discriminator: str | None = None) -> int:
        rows = self._rows(table, discriminator)
        return len({row["PKEY_SRC_OBJECT"].split("|")[0] for row in rows if row.get("PKEY_SRC_OBJECT")})

    # -- ETL ---------------------------------------------------------------
    def delete_discriminator_rows(self, table, discriminator: str) -> None:
        key = (table.schema, table.name)
        self.store[key] = [r for r in self.store.get(key, []) if r.get("DATA_SOURCE") != discriminator]

    def call_procedure_in_schema(self, schema: str, procedure: str) -> str:
        self.called_procedures.append(procedure)
        return "JOB_RUN_ID=test-run-123 Completed"


def _spine_rows():
    """Same spine data on both sides, so spine verdicts do not interfere.

    One table, two DATA_SOURCE sides -- the v5 model.
    """
    def sided(rows):
        return (
            [{**r, "DATA_SOURCE": IDQ_VALUE} for r in rows]
            + [{**r, "DATA_SOURCE": SNOWFLAKE_VALUE} for r in rows]
        )
    valid = [{"INDV_ID": 1}, {"INDV_ID": 2}]
    roles = [{"PKEY_SRC_OBJECT": "1|Member"}, {"PKEY_SRC_OBJECT": "2|Member"}]
    return {
        (SCHEMA, "STG_TRS_VALID_MEMBERS"): sided(valid),
        (SCHEMA, "C_S_TRS_PTY_RLE"): sided(roles),
    }


def _phone_rows():
    return [
        {"PKEY_SRC_OBJECT": "1|Member", "VERSION_SEQ": 1},
        {"PKEY_SRC_OBJECT": "2|Member", "VERSION_SEQ": 1},
    ]


def test_copy_input_table_goes_to_etl_wrk():
    oracle = FakeOracle({"STG_TRS_D_LU_TOA": [{"TOA_CD": "A"}, {"TOA_CD": "B"}]})
    snowflake = FakeSnowflake()
    results, overall = copy_service.run_copy(oracle, snowflake, ["STG_TRS_D_LU_TOA"])
    assert overall == "COMPLETED"
    assert results[0].status == "COPIED"
    assert results[0].oracle_row_count == 2 and results[0].snowflake_row_count == 2
    assert len(snowflake.store[(SCHEMA, "STG_TRS_D_LU_TOA")]) == 2


def test_copy_expected_table_loads_idq_side_only():
    # The v5 form of the WORK-empty trap, proved with fakes: the
    # table starts with stale rows on BOTH sides, copy truncates
    # the whole table and loads IDQ rows only -- no SNOWFLAKE rows.
    oracle = FakeOracle({"C_S_TRS_PTY": _phone_rows()})
    snowflake = FakeSnowflake({(SCHEMA, "C_S_TRS_PTY"): [
        {"PKEY_SRC_OBJECT": "STALE|Member", "VERSION_SEQ": 9, "DATA_SOURCE": SNOWFLAKE_VALUE},
        {"PKEY_SRC_OBJECT": "OLD|Member", "VERSION_SEQ": 9, "DATA_SOURCE": IDQ_VALUE},
    ]})
    results, overall = copy_service.run_copy(oracle, snowflake, ["C_S_TRS_PTY"])
    assert overall == "COMPLETED"
    assert results[0].status == "COPIED"
    rows = snowflake.store[(SCHEMA, "C_S_TRS_PTY")]
    assert len(rows) == 2 and all(r["DATA_SOURCE"] == IDQ_VALUE for r in rows)


def test_copy_missing_table_is_partial_not_failed():
    oracle = FakeOracle({})
    snowflake = FakeSnowflake()
    results, overall = copy_service.run_copy(oracle, snowflake, ["REF_JUNK_NAME_LIST"])
    assert results[0].status == "SKIPPED_MISSING"
    assert overall == "PARTIAL"


def test_compare_match_when_both_sides_equal():
    store = _spine_rows()
    store[(SCHEMA, "C_S_TRS_PTY_RLE_PHN")] = (
        [{**r, "DATA_SOURCE": IDQ_VALUE} for r in _phone_rows()]
        + [{**r, "DATA_SOURCE": SNOWFLAKE_VALUE} for r in _phone_rows()]
    )
    dims, spine, verdict = compare_service.run_compare(FakeSnowflake(store), None, ["Phones"], 20)
    assert verdict == "MATCH"
    assert dims[0].table == "C_S_TRS_PTY_RLE_PHN"
    assert dims[0].oracle_only_keys == 0 and dims[0].snowflake_only_keys == 0


def test_compare_mismatch_when_work_is_missing_a_key():
    store = _spine_rows()
    store[(SCHEMA, "C_S_TRS_PTY_RLE_PHN")] = (
        [{**r, "DATA_SOURCE": IDQ_VALUE} for r in _phone_rows()]
        + [{**r, "DATA_SOURCE": SNOWFLAKE_VALUE} for r in _phone_rows()[:1]]  # missing member 2
    )
    dims, spine, verdict = compare_service.run_compare(FakeSnowflake(store), None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    assert dims[0].oracle_only_keys == 1
    assert dims[0].oracle_only_sample == ["2|Member"]


def test_compare_partial_when_a_table_errors():
    store = _spine_rows()
    store[(SCHEMA, "C_S_TRS_PTY_RLE_PHN")] = (
        [{**r, "DATA_SOURCE": IDQ_VALUE} for r in _phone_rows()]
        + [{**r, "DATA_SOURCE": SNOWFLAKE_VALUE} for r in _phone_rows()]
    )
    fake = FakeSnowflake(store)
    fake.raise_on_count.add((SCHEMA, "C_S_TRS_PTY_RLE_PHN"))
    dims, spine, verdict = compare_service.run_compare(fake, None, ["Phones"], 20)
    assert verdict == "PARTIAL"
    assert dims[0].oracle_row_count == -1


def test_etl_runs_workflows_in_order_and_parses_job_run_id():
    fake = FakeSnowflake()
    results, overall, job_run_id = etl_service.run_etl(fake, ["toa", "ongoing"])
    assert overall == "COMPLETED"
    assert job_run_id == "test-run-123"
    assert fake.called_procedures == [
        "sp_etl_run_wf_TRS_Stage_Load_TOA",
        "sp_etl_run_wf_TRS_Stage_Load_1_Ongoing",
    ]


def test_etl_unknown_workflow_is_rejected_before_any_call():
    fake = FakeSnowflake()
    try:
        etl_service.run_etl(fake, ["nope"])
    except ValueError:
        pass
    else:
        raise AssertionError("Unknown workflow was not rejected")
    assert fake.called_procedures == []


def test_compare_empty_filter_is_rejected_not_false_match():
    try:
        compare_service.run_compare(FakeSnowflake(_spine_rows()), None, ["NoSuchDimension"], 20)
    except ValueError:
        pass
    else:
        raise AssertionError("Empty filter result was not rejected")


def test_etl_empty_workflow_list_is_rejected():
    try:
        etl_service.run_etl(FakeSnowflake(), [])
    except ValueError:
        pass
    else:
        raise AssertionError("Empty workflow list was not rejected")


def test_etl_clears_snowflake_side_and_preserves_idq_side():
    store = {(SCHEMA, "C_S_TRS_PTY_RLE_PHN"): [
        {"PKEY_SRC_OBJECT": "1|Member", "DATA_SOURCE": IDQ_VALUE},
        {"PKEY_SRC_OBJECT": "STALE|Member", "DATA_SOURCE": SNOWFLAKE_VALUE},
    ]}
    fake = FakeSnowflake(store)
    results, overall, _ = etl_service.run_etl(fake, ["toa"])
    assert overall == "COMPLETED"
    assert results[0]["workflow"] == "(clear-snowflake)"
    rows = fake.store[(SCHEMA, "C_S_TRS_PTY_RLE_PHN")]
    assert rows == [{"PKEY_SRC_OBJECT": "1|Member", "DATA_SOURCE": IDQ_VALUE}]
