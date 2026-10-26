"""SQLite harness tests: the REAL compare service, against a
real (SQLite) database loaded from test_harness_data/*.sql.

These tests replace the FakeSnowflake dict tests for the
compare's SQL behaviour -- not for its verdict logic, which
test_services.py still covers with fakes.  Each test:
  1. builds a fresh SQLite engine (all catalog tables, empty),
  2. loads scenario SQL (common spine first, then the case),
  3. runs run_compare() -- the production service, with the
     production SnowflakeRepository, no fake in sight,
  4. asserts on counts, keys, samples, versions and verdict,
     not just the verdict string.

To add a case: add a SQL file in test_harness_data/ (see its
README), then add a test here following the pattern below.
"""

from tests.sqlite_harness import harness_repo
from app.services import compare_service


def _dimension(dims, table):
    """The DimensionCompare for one table, or raise a clear error."""
    for d in dims:
        if d.table == table:
            return d
    raise AssertionError(f"No dimension compared for {table}; got {[d.table for d in dims]}")


def _coverage(spine, table):
    """The coverage entry for one table, from the party-role spine."""
    role = next(s for s in spine if "Party-role" in s.spine)
    for entry in role.coverage or []:
        if entry["table"] == table:
            return entry
    raise AssertionError(f"No coverage entry for {table}")


# -- Success cases ---------------------------------------------------------

def test_sqlite_match_phones():
    # 01: identical Phones on both sides -> MATCH.
    _engine, repo = harness_repo("00_common_spine.sql", "01_match_phones.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MATCH"
    phones = _dimension(dims, "C_S_TRS_PTY_RLE_PHN")
    assert (phones.oracle_row_count, phones.snowflake_row_count) == (2, 2)
    assert phones.count_diff == 0
    assert (phones.matched_keys, phones.oracle_only_keys, phones.snowflake_only_keys) == (2, 0, 0)
    assert (phones.version_matched_keys, phones.version_oracle_only_keys) == (2, 0)


def test_sqlite_full_match_all_dimensions():
    # 01 + 02, no filter: every other dimension is empty on both
    # sides (empty-vs-empty matches), spine matches -> MATCH.
    # This is the closest the harness gets to a whole-run check
    # without the ETL: it proves the spine section does not
    # manufacture a mismatch out of empty tables.
    _engine, repo = harness_repo("00_common_spine.sql", "01_match_phones.sql", "02_match_demographics.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, None, 20)
    assert verdict == "MATCH"
    assert all(d.oracle_row_count >= 0 for d in dims)
    assert all(s.oracle_only_keys == 0 and s.snowflake_only_keys == 0 for s in spine)


def test_sqlite_exceptions_match():
    # 09: same bad records both sides -> MATCH, even though the
    # exception dimension always carries its "no unique key" note.
    # The note is informational; it must not turn a match into a
    # mismatch, and the test asserts both facts together.
    _engine, repo = harness_repo("00_common_spine.sql", "09_exceptions_match.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Exceptions"], 20)
    assert verdict == "MATCH"
    exc = _dimension(dims, "EXC_STG_BAD_REC_MEMB")
    assert (exc.oracle_row_count, exc.snowflake_row_count) == (2, 2)
    assert exc.matched_keys == 2
    assert "no unique key" in exc.message


# -- Failure cases: dimension rows -----------------------------------------

def test_sqlite_missing_on_snowflake():
    # 03: IDQ has 3 phones, Snowflake 2 -> the missing key is the
    # triage pointer, so assert the sample, not just the count.
    _engine, repo = harness_repo("00_common_spine.sql", "03_missing_on_snowflake.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    phones = _dimension(dims, "C_S_TRS_PTY_RLE_PHN")
    assert (phones.oracle_row_count, phones.snowflake_row_count) == (3, 2)
    assert phones.count_diff == -1
    assert (phones.matched_keys, phones.oracle_only_keys, phones.snowflake_only_keys) == (2, 1, 0)
    assert phones.oracle_only_sample == ["3|Member"]


def test_sqlite_extra_on_snowflake():
    # 04: Snowflake produced a phone IDQ did not (member 4, who
    # is not even in the valid spine) -> snowflake-only, not a
    # spine verdict: the spine tables themselves still match.
    _engine, repo = harness_repo("00_common_spine.sql", "04_extra_on_snowflake.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    phones = _dimension(dims, "C_S_TRS_PTY_RLE_PHN")
    assert (phones.oracle_row_count, phones.snowflake_row_count) == (2, 3)
    assert (phones.matched_keys, phones.oracle_only_keys, phones.snowflake_only_keys) == (2, 0, 1)
    assert phones.snowflake_only_sample == ["4|Member"]
    assert all(s.oracle_only_keys == 0 and s.snowflake_only_keys == 0 for s in spine)


def test_sqlite_version_mismatch_despite_matching_pkey_sets():
    # 05: THE regression guard.  PKEY sets are identical, so a
    # PKEY-only compare would report MATCH.  The version set is
    # what catches the missing closed version (2|Member v2).
    _engine, repo = harness_repo("00_common_spine.sql", "05_version_mismatch.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    phones = _dimension(dims, "C_S_TRS_PTY_RLE_PHN")
    assert (phones.oracle_only_keys, phones.snowflake_only_keys) == (0, 0)
    assert phones.version_oracle_only_keys == 1
    assert phones.version_snowflake_only_keys == 0


def test_sqlite_duplicate_keys_are_not_hidden_by_set_compare():
    # 06: set compare alone says MATCH (same distinct keys);
    # the count and the duplicate message are what catch it.
    _engine, repo = harness_repo("00_common_spine.sql", "06_duplicate_keys.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    phones = _dimension(dims, "C_S_TRS_PTY_RLE_PHN")
    assert (phones.oracle_row_count, phones.snowflake_row_count) == (3, 2)
    assert (phones.matched_keys, phones.oracle_only_keys, phones.snowflake_only_keys) == (2, 0, 0)
    assert "Duplicate compare keys on the IDQ side" in phones.message


# -- Failure cases: spine and coverage -------------------------------------

def test_sqlite_spine_gap_despite_matching_dimension():
    # 07 (no common spine -- the file loads its own): Phones
    # match perfectly, but the valid-member spine is missing
    # member 3 on the Snowflake side -> verdict MISMATCH, driven
    # by the spine alone.  A dimension-only check would miss it.
    _engine, repo = harness_repo("07_spine_gap.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    assert _dimension(dims, "C_S_TRS_PTY_RLE_PHN").matched_keys == 2
    valid = next(s for s in spine if "Valid-member" in s.spine)
    assert (valid.oracle_keys, valid.snowflake_keys) == (3, 2)
    assert valid.oracle_only_keys == 1
    assert valid.oracle_only_sample == ["3"]


def test_sqlite_coverage_gap():
    # 08: Names covers 3 members IDQ, 2 Snowflake.  Assert the
    # coverage entry itself (the triage view), not just the
    # dimension verdict -- coverage is reported, not
    # verdict-driving, so a test that only checked the verdict
    # would not prove coverage works at all.  This test also
    # proves the SQLite spine expression (SUBSTR/INSTR, not
    # SPLIT_PART) produces the right numbers.
    _engine, repo = harness_repo("00_common_spine.sql", "08_coverage_gap.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Names"], 20)
    assert verdict == "MISMATCH"
    cov = _coverage(spine, "C_S_TRS_PTY_NM")
    assert (cov["oracle_spine_ids"], cov["snowflake_spine_ids"], cov["diff"]) == (3, 2, -1)


# -- The pre-ETL state (not a failure) --------------------------------------

def test_sqlite_pre_etl_empty_snowflake_side():
    # 10: copy done, ETL not run -> Snowflake side empty.
    # Expected verdict is MISMATCH, and that is CORRECT: the
    # compare is reporting an empty side, not a broken ETL.
    # When the ETL lands, this scenario is retired (see the
    # SQL file's header), not edited to pass.
    _engine, repo = harness_repo("00_common_spine.sql", "10_pre_etl_empty_snowflake.sql")
    dims, spine, verdict = compare_service.run_compare(repo, None, ["Phones"], 20)
    assert verdict == "MISMATCH"
    phones = _dimension(dims, "C_S_TRS_PTY_RLE_PHN")
    assert (phones.oracle_row_count, phones.snowflake_row_count) == (2, 0)
    assert (phones.matched_keys, phones.oracle_only_keys, phones.snowflake_only_keys) == (0, 2, 0)
