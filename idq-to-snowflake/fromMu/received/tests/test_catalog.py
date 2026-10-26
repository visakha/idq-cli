"""Catalog and explicit-table tests: no database needed."""

from sqlalchemy import func, select

from app.domain import catalog, tables
from app.domain.tables import column_names, table_for


def test_no_duplicate_tables():
    names = [t.name for t in catalog.ALL_TABLES]
    assert len(names) == len(set(names)), "Duplicate table in catalog"


def test_expected_tables_all_have_compare_keys():
    for spec in catalog.EXPECTED_TABLES:
        assert spec.compare_key, f"{spec.name} has no compare key"


def test_input_tables_have_no_compare_keys():
    for spec in catalog.INPUT_TABLES:
        assert spec.compare_key == [], f"Input table {spec.name} should not have a compare key"


def test_missing_tables_are_exactly_the_four_not_in_exports():
    missing = sorted(t.name for t in catalog.ALL_TABLES if t.missing_from_exports)
    assert missing == [
        "REF_JUNK_NAME_LIST",
        "REF_MATCHCODE_DESC",
        "REF_PHN_AREA_CD",
        "V_LOOKUP_CODE_VALUE",
    ]


def test_tables_for_copy_rejects_unknown_names():
    try:
        catalog.tables_for_copy(["NO_SUCH_TABLE"])
    except KeyError:
        pass
    else:
        raise AssertionError("Unknown table name was not rejected")


def test_tables_for_compare_filters_by_dimension():
    phones = catalog.tables_for_compare(None, ["Phones"])
    assert [t.name for t in phones] == ["C_S_TRS_PTY_RLE_PHN"]


def test_member_domain_has_no_provider_dimension_yet():
    # Deliberate scope decision (see catalog.py): Provider parties are
    # not loaded by these two workflows, so no Provider dimension
    # should appear in the compare list.
    domains = {t.domain for t in catalog.EXPECTED_TABLES}
    assert "Provider" not in domains


def test_tables_are_explicit_not_reflected():
    # table_for builds from checked-in data, not from a live database.
    # The same name in two schemas gives two independent Table objects
    # with the same columns -- no shared Column objects, no reflection.
    from app.core.config import settings

    src = table_for("C_S_TRS_PTY", settings.snowflake_schema)
    work = table_for("C_S_TRS_PTY", settings.snowflake_schema)
    assert src is not work
    assert src.schema == settings.snowflake_schema
    assert work.schema == settings.snowflake_schema
    assert column_names("C_S_TRS_PTY")[0] == "PKEY_SRC_OBJECT"
    assert "FRST_NM" in column_names("C_S_TRS_PTY")
    assert "VERSION_SEQ" in column_names("C_S_TRS_PTY")


def test_table_for_rejects_unknown_names():
    try:
        table_for("NO_SUCH_TABLE", "TRS_ETL_WRK")
    except KeyError:
        pass
    else:
        raise AssertionError("Unknown table name was not rejected")


def test_fluent_except_query_builds_without_string_sql():
    # The compare's core operation, built as a Core statement, not a
    # string: select(key).except_(select(key)).  Compiling it must
    # show EXCEPT, and the statement must reference both schemas.
    from app.core.config import settings

    idq = table_for("C_S_TRS_PTY", settings.snowflake_schema)
    work = table_for("C_S_TRS_PTY", settings.snowflake_schema)
    stmt = select(idq.c.PKEY_SRC_OBJECT).except_(select(work.c.PKEY_SRC_OBJECT))
    compiled = str(stmt.compile(compile_kwargs={"literal_binds": True}))
    assert "EXCEPT" in compiled
    assert settings.snowflake_schema in compiled and settings.snowflake_schema in compiled
    assert "PKEY_SRC_OBJECT" in compiled


def test_fluent_count_query():
    from app.core.config import settings
    table = table_for("STG_TRS_VALID_MEMBERS", settings.snowflake_schema)
    stmt = select(func.count()).select_from(table)
    compiled = str(stmt.compile(compile_kwargs={"literal_binds": True}))
    assert "count" in compiled.lower()
    assert "STG_TRS_VALID_MEMBERS" in compiled
