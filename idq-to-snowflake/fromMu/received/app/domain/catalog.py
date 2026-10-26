"""The table catalog: the single source of truth for copy and compare.

This file lists tables and their roles, domains, dimensions and
compare keys.  It does NOT list columns: column lists live in
app/domain/tables.py (explicit, generated, checked in).  Keeping the
two separate is deliberate -- the catalog is the business view (what
a table is for), tables.py is the physical view (what columns it
has), and neither is built by reflecting a database at runtime.


Every table the Snowflake ETL reads or writes appears here exactly
once, with:
  * its Oracle schema (STAGING / HHS_MDM / RDM / None if unknown),
  * its copy role,
  * its domain and dimension (the user's terminology -- see below),
  * its compare key (for target tables only).

Copy roles (v5 -- single schema, discriminator):
  * "input"    -- a true Oracle input.  Copied once, from Oracle,
                 into TRS_ETL_WRK in the source database
                 (MDM_ETL_TRS.TRS_ETL_WRK for this project), where the
                 Snowflake ETL reads it.  Input rows are the shared
                 Oracle input, not IDQ-vs-Snowflake data, so input
                 tables carry NO discriminator column.
  * "expected" -- an IDQ-produced target.  Copied from Oracle (after
                 the daily IDQ run) into the SAME TRS_ETL_WRK table the
                 Snowflake ETL then populates, with the discriminator
                 DATA_SOURCE='IDQ'.  The Snowflake ETL writes its
                 rows into the same table with DATA_SOURCE='SNOWFLAKE'.
                 NEVER copy an expected table's IDQ rows without the
                 discriminator, and never pre-load SNOWFLAKE rows:
                 the Snowflake procedures are insert-only with
                 existing-key guards, so a pre-loaded SNOWFLAKE side
                 would suppress the Snowflake rows it is supposed to
                 produce and corrupt the compare.  This is the most
                 important trap in the whole design, in its v5 form:
                 the trap is no longer "WORK must start empty" but
                 "the SNOWFLAKE side must start empty" -- the ETL
                 step deletes DATA_SOURCE='SNOWFLAKE' rows before
                 calling the runners, and the copy step truncates
                 the whole target table (both sides) before loading
                 IDQ rows.

Discriminator, in the user's words: a pivotal column that tells
whether a row in a target table came from IDQ or from Snowflake,
so the same table holds both the actual and the expected data.
Column: DATA_SOURCE (config: discriminator_column).  Values:
'IDQ' and 'SNOWFLAKE' (config: discriminator_idq_value /
discriminator_snowflake_value).  "Source tables" in that sentence
means the IDQ side's tables and "target tables" the Snowflake
side's tables -- which are now the same physical table, told
apart by DATA_SOURCE.  It does not mean the Oracle input tables:
those have one side only (Oracle), so a discriminator on them
would carry a single meaningless value.

Domains and dimensions (user's terminology, adopted here):
  * Domain is the parent: Member (the only domain these two workflows
    load).  Provider is NOT loaded as a party by these workflows --
    PCP relationships reference providers by TPI, they do not create
    provider parties -- so there is deliberately no Provider dimension
    list yet.  Add one only when a Provider workflow is in scope.
  * Dimension is a slice within the domain: Demographics, Names,
    Alternate IDs, Plans, TOA, Phones, Emails, Addresses, Managed
    Attributes, Relationships, Exceptions, Spine, Deactivation, and
    Reference (for the TOA catalogue, which is reference data, not a
    Member dimension -- it is kept under domain "Reference" so it
    cannot be mistaken for a Member slice).

Compare keys:
  * Most C_S_* tables: ["PKEY_SRC_OBJECT"].  Note on versions: the
    same PKEY can appear with several VERSION_SEQ values in timeline
    tables (relationships, and any table where a row is closed and
    re-opened).  The compare therefore checks BOTH the PKEY set and
    the (PKEY_SRC_OBJECT, VERSION_SEQ) set, and reports counts per
    PKEY, so a missing closed version cannot hide behind a matching
    PKEY set.  See compare_service.py.
  * Tables without a PKEY use their natural key (see the table below).
  * EXC_STG_BAD_REC_MEMB has no unique key at all: its compare key is
    the (SRC_SYS_ID_1, EXCEPTION_CODE, ATTRIBUTE_NAME,
    ATTRIBUTE_VALUE, MAPPING_NAME) tuple, reported as a set, plus a
    duplicate-row count, so duplicates are visible rather than
    silently collapsed.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel

CopyRole = Literal["input", "expected"]


class TableSpec(BaseModel):
    """One table, as the copy and compare jobs need to know it."""

    name: str
    oracle_schema: str | None  # None = unknown / not in the supplied exports
    copy_role: CopyRole
    domain: str
    dimension: str
    compare_key: list[str] = []  # empty for input-only tables
    missing_from_exports: bool = False


# -- Input tables -----------------------------------------------------------
# Oracle schema is the schema the table lives in on the Oracle side.
# REF_PHN_AREA_CD is a TRS input like any other in v5: it lives in
# TRS_ETL_WRK with the other inputs.  The ETL helper that used to qualify
# it as RDM.REF_PHN_AREA_CD (v4: MDM_ETL_COMMON.REF_PHN_AREA_CD) must
# now read it unqualified from TRS_ETL_WRK, like every other helper --
# see the guide, "ETL-package changes in v5".  COMMON holds framework
# objects (job control, metrics, shared functions), not this table.
INPUT_TABLES: list[TableSpec] = [
    TableSpec(name="STG_TRS_CD_REF", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Reference — Code"),
    TableSpec(name="STG_TRS_CV_ED_MCI_EDG_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Reference — Crosswalk"),
    TableSpec(name="STG_TRS_DC_CASES", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Cases"),
    TableSpec(name="STG_TRS_DC_CASE_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Case Individuals"),
    TableSpec(name="STG_TRS_DC_PRIMARY_PAYEE", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Payees"),
    TableSpec(name="STG_TRS_D_CV_DC_MCI_ALIAS", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC/MCI Aliases"),
    TableSpec(name="STG_TRS_D_CV_DC_MCI_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC/MCI Individuals"),
    TableSpec(name="STG_TRS_D_CV_DC_MRG_SPRT_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — Merged/Split Individuals"),
    TableSpec(name="STG_TRS_D_CV_ED_MCI_EDG_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — EDG Individuals"),
    TableSpec(name="STG_TRS_D_CV_MCI_EDG_INDV_TOA", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — EDG TOA"),
    TableSpec(name="STG_TRS_D_DC_ALIAS", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Aliases"),
    TableSpec(name="STG_TRS_D_DC_CASES", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Cases (detail)"),
    TableSpec(name="STG_TRS_D_DC_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Individuals"),
    TableSpec(name="STG_TRS_D_DC_PRIMARY_PAYEE", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Primary Payees"),
    TableSpec(name="STG_TRS_D_DC_RELATIONSHIPS", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Relationships"),
    TableSpec(name="STG_TRS_D_DC_RELATIONSHIPS_A", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Relationships (archive)"),
    TableSpec(name="STG_TRS_D_INDV_ADDR", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — Individual Addresses"),
    TableSpec(name="STG_TRS_D_IN_MANAGED_CARE", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — Managed Care"),
    TableSpec(name="STG_TRS_D_LU_TOA", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — TOA Lookup"),
    TableSpec(name="STG_TRS_H_DC_INDV", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Source — DC Individual History"),
    TableSpec(name="EXC_LOOKUP_CODE_VALUE", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Reference — Exception Codes"),
    TableSpec(name="LOOKUP_CODE_VALUE", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Reference — Code Values"),
    TableSpec(name="REF_DYLGHT_SVNGS_TM", oracle_schema="STAGING", copy_role="input", domain="Member", dimension="Reference — Daylight Saving"),
    TableSpec(name="C_B_PTY_RLE_ALT_ID", oracle_schema="HHS_MDM", copy_role="input", domain="Member", dimension="Reference — MDM Alt-ID Base"),
    TableSpec(name="C_B_PTY_RLE_ALT_ID_XREF", oracle_schema="HHS_MDM", copy_role="input", domain="Member", dimension="Reference — MDM Alt-ID Xref"),
    TableSpec(name="C_B_PTY_RLE_REL_XREF", oracle_schema="HHS_MDM", copy_role="input", domain="Member", dimension="Reference — MDM Relationship Xref"),
    # Missing from the supplied Oracle exports -- see sql/04_missing_tables.sql.
    TableSpec(name="V_LOOKUP_CODE_VALUE", oracle_schema=None, copy_role="input", domain="Member", dimension="Reference — Code Values (view)", missing_from_exports=True),
    TableSpec(name="REF_JUNK_NAME_LIST", oracle_schema=None, copy_role="input", domain="Member", dimension="Reference — Junk Names", missing_from_exports=True),
    TableSpec(name="REF_MATCHCODE_DESC", oracle_schema=None, copy_role="input", domain="Member", dimension="Reference — Match Codes", missing_from_exports=True),
    TableSpec(name="REF_PHN_AREA_CD", oracle_schema="RDM", copy_role="input", domain="Member", dimension="Reference — Phone Area Codes", missing_from_exports=True),
]

# -- Expected (IDQ target) tables -------------------------------------------
EXPECTED_TABLES: list[TableSpec] = [
    TableSpec(name="STG_TRS_VALID_MEMBERS", oracle_schema="STAGING", copy_role="expected", domain="Member", dimension="Spine — Valid Members", compare_key=["INDV_ID", "SRC_TBL"]),
    TableSpec(name="C_S_TRS_PTY", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Demographics", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Party Role", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_NM", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Names", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_ALT_ID", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Alternate IDs", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_PLN", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Plans", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_TOA", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="TOA", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_PHN", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Phones", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_EADDR", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Emails", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_ADDR", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Addresses", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="DQM_ADDRESS", oracle_schema="STAGING", copy_role="expected", domain="Member", dimension="Addresses — Audit", compare_key=["PTY_SRC_KEY", "ADDR_SRC_KEY"]),
    TableSpec(name="STG_TRS_D_UNQ_ADDR", oracle_schema="STAGING", copy_role="expected", domain="Member", dimension="Addresses — Unique", compare_key=["ADDR_ID"]),
    TableSpec(name="C_S_TRS_PTY_MNG_ATTR", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Managed Attributes", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_REL", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Relationships — Member to Member", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_TRS_PTY_RLE_REL_PROV", oracle_schema="HHS_MDM", copy_role="expected", domain="Member", dimension="Relationships — Member to PCP", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="EXC_STG_BAD_REC_MEMB", oracle_schema="STAGING", copy_role="expected", domain="Member", dimension="Exceptions", compare_key=["SRC_SYS_ID_1", "EXCEPTION_CODE", "ATTRIBUTE_NAME", "ATTRIBUTE_VALUE", "MAPPING_NAME"]),
    TableSpec(name="STG_TRS_DEACTIVED_MEMBERS", oracle_schema="STAGING", copy_role="expected", domain="Member", dimension="Deactivation — Party Capture", compare_key=["INDV_ID"]),
    TableSpec(name="STG_TRS_DEACTIVATED_RELATIONSHIPS", oracle_schema="STAGING", copy_role="expected", domain="Member", dimension="Deactivation — Relationship Capture", compare_key=["PKEY_SRC_OBJECT"]),
    TableSpec(name="C_S_LU_TOA", oracle_schema="HHS_MDM", copy_role="expected", domain="Reference", dimension="TOA Catalogue", compare_key=["PKEY_SRC_OBJECT"]),
]

ALL_TABLES: list[TableSpec] = INPUT_TABLES + EXPECTED_TABLES


def get_table(name: str) -> TableSpec:
    """Look up a table by name (case-insensitive). Raises KeyError."""
    upper = name.upper()
    for spec in ALL_TABLES:
        if spec.name == upper:
            return spec
    raise KeyError(f"Unknown table: {name!r}. See GET /config/tables for the allowlist.")


def tables_for_copy(requested: list[str] | None) -> list[TableSpec]:
    """Resolve a copy request's table list, or all tables in order.

    Order matters: inputs first (so a failure stops before any target
    is touched), then expected tables.  Within each group, tables are
    in catalog order, which is alphabetical by name except where a
    dependency note says otherwise -- the copy itself has no
    dependencies, so alphabetical is fine and auditable.
    """
    if not requested:
        return sorted(INPUT_TABLES, key=lambda t: t.name) + sorted(EXPECTED_TABLES, key=lambda t: t.name)
    return [get_table(name) for name in requested]


def tables_for_compare(requested_domains: list[str] | None, requested_dimensions: list[str] | None) -> list[TableSpec]:
    """Expected tables filtered by domain and/or dimension (exact match)."""
    out = EXPECTED_TABLES
    if requested_domains:
        domains = {d for d in requested_domains}
        out = [t for t in out if t.domain in domains]
    if requested_dimensions:
        dims = {d for d in requested_dimensions}
        out = [t for t in out if t.dimension in dims]
    return out


# Spine tables: the two keys every dimension is measured against.
#   * STG_TRS_VALID_MEMBERS.INDV_ID -- the valid-member spine.
#   * C_S_TRS_PTY_RLE.PKEY_SRC_OBJECT -- the party-role spine
#     (format INDV_ID|Member for Member parties).
SPINE_VALID_MEMBERS = "STG_TRS_VALID_MEMBERS"
SPINE_PARTY_ROLE = "C_S_TRS_PTY_RLE"
