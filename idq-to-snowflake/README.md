# IDQ → Snowflake stored procedures

Drop-in Snowflake replacements for the 39 IDQ mappings of the six stage-load workflows in `docs/`. Unlike the Oracle
port in [`idq-to-oracle/`](../idq-to-oracle/README.md), **nothing is assumed to exist**: the IDQ mapplets and rules of
[`docs/mappings/000_mapplets.md`](../docs/mappings/000_mapplets.md) are written out here as Snowflake SQL functions.


## How is this file generated?
Hand written by the coding agent


| Workflow (IDQ export) | Mappings | Folder | Run script |
|---|---|---|---|
| `docs/wf_ECI_Stage_Load.xml` | 9 | [wf_ECI_Stage_Load](wf_ECI_Stage_Load/) | [run_wf_ECI_Stage_Load.sql](wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql) |
| `docs/wf_FSS_Stage_Load.xml` | 6 | [wf_FSS_Stage_Load](wf_FSS_Stage_Load/) | [run_wf_FSS_Stage_Load.sql](wf_FSS_Stage_Load/run_wf_FSS_Stage_Load.sql) |
| `docs/wf_TTF_Stage_Load.xml` | 4 | [wf_TTF_Stage_Load](wf_TTF_Stage_Load/) | [run_wf_TTF_Stage_Load.sql](wf_TTF_Stage_Load/run_wf_TTF_Stage_Load.sql) |
| `docs/wf_WIC_Stage_Load.xml` | 5 | [wf_WIC_Stage_Load](wf_WIC_Stage_Load/) | [run_wf_WIC_Stage_Load.sql](wf_WIC_Stage_Load/run_wf_WIC_Stage_Load.sql) |
| `docs/wf_TRS_Stage_Load_1_Ongoing.xml` | 14 | [wf_TRS_Stage_Load_1_Ongoing](wf_TRS_Stage_Load_1_Ongoing/) | [run_wf_TRS_Stage_Load_1_Ongoing.sql](wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql) |
| `docs/wf_CRE_Stage_Load_Ongoing.xml` | 1 | [wf_CRE_Stage_Load_Ongoing](wf_CRE_Stage_Load_Ongoing/) | [run_wf_CRE_Stage_Load_Ongoing.sql](wf_CRE_Stage_Load_Ongoing/run_wf_CRE_Stage_Load_Ongoing.sql) |

Each procedure is documented, one page per mapping, in [`docs-from-snowflake-db-scripts/`](../docs-from-snowflake-db-scripts/README.md). Those pages
are generated from the procedure headers here by `ext-tools/snowflake_spec.py`; after changing a header, regenerate:

```sh
python -I ext-tools/snowflake_spec.py
```

> **Not compiled.** No Snowflake account was available while these were written. The SQL was checked statically
> (balanced SQL, every `INTO` has as many values as columns, every value and router condition names a column of the
> query, no `DELETE` / `TRUNCATE` / `DROP`). Install into a scratch schema first and compare the results with an IDQ
> run (or the `ORA_SP` engine) on the same input.

> **Insert only.** The procedures never `TRUNCATE`, `DELETE` or `DROP`, so they are safe to call against production
> data. The IDQ *Truncate target table* option and the `DD_DELETE` update strategies are deliberately left out; every
> such place is marked `-- Not performed: ...`. `InsertOnlySqlTest` fails the build if one of those statements shows up
> outside a comment.

## Scope: timeline, validations and bad data are IN

The Java port and the IDMC specs leave the stale MDM timeline out. For this port the timeline, every data validation
and every bad-data path are part of the job, exactly as IDQ runs them, and marked in the comments:

| Marker | Means | Examples |
|---|---|---|
| `TIMELINE` | MDM timeline logic: `VERSION_SEQ`, version ranks, `PERIOD_*`, `TIMELINE_ACTION`, DST correction, the timeline mapplet | TRS relationships emit an end-dated row twice and re-rank; TRS addresses number versions |
| `VALIDATION` | a rule that decides an exception code or a route | name, gender, birth date, race / ethnicity / language, suffix, phone, e-mail, SSN, Medicaid / member id, address score |
| `BAD DATA` | what happens to a bad value or row: blanked, cleaned, truncated, logged, rejected | future birth date loaded as NULL, invalid SSN blanked and dropped, unique-key rejects, phone cut to 10 characters |

Every procedure header has one paragraph per marker.

## Naming

| Object | Name | Where |
|---|---|---|
| One procedure per IDQ mapping | `sp_snow_main_<mapping name>` | `<workflow>/sp_snow_main_<mapping>.sql` |
| Mapplets, rules and IDQ helpers shared by every mapping | `fn_snow_helperNN_common` (01-37 scalar, 40-47 lookups) | `common/01_snow_common_functions.sql`, `common/02_snow_common_lookups.sql` |
| Helper used by one mapping only | `fn_snow_helperNN_<mapping>` | `<workflow>/fn_snow_helperNN_<mapping>.sql` (the two TRS normalizers) |
| Shared helper procedures | `sp_snow_helperNN_common` | none were needed: each mapping is one set-based statement |

## Mapplets and rules

| IDQ mapplet / rule | Snowflake | Notes |
|---|---|---|
| `mplt_Name_Standardization_Indv_Member` (+ TTF `CopyOf_`) | `fn_snow_helper15_common` | prefix / suffix / junk-name lookups joined by the caller |
| `mplt_Name_Standardization_Trailing_Num_Removal` | `fn_snow_helper14_common` (steps 11-13) | the "middle name returns the last name" quirk kept |
| `mplt_BirthDate_Validation` | `fn_snow_helper16_common` | |
| `mplt_Gender_Validation` | `fn_snow_helper17_common` | first character only (string(1) port) |
| `mplt_Race_Validation`, `mplt_Ethnicity_Validation`, `mplt_Language_Validation` | `fn_snow_helper18_common` + `V_LOOKUP_CODE_VALUE` | |
| `mplt_Race_Ind_Validation` | `fn_snow_helper19_common` | |
| `rule_Suffix_Std` | `fn_snow_helper20_common` + `fn_snow_helper42_common` | lookup without a code-type filter |
| `mplt_Date_Greater_Than_Fifty_Years` | `fn_snow_helper21_common` | text comparison kept, see the open risks |
| `rule_email_validation_v01` (+ local part, domain) | `fn_snow_helper22_common` | |
| `rule_Phone_Std` | `fn_snow_helper23_common` + `fn_snow_helper44_common` + `fn_snow_helper24_common` | area code from `RDM.REF_PHN_AREA_CD` |
| `rule_Phone_Extension_Std` | `fn_snow_helper25_common` | |
| `rule_USA_SSN_Validation_post_June2011` | `fn_snow_helper26_common` | |
| `rule_MEDICAID_ID_Std`, `rule_Member_Id_Std` | `fn_snow_helper27_common`, `fn_snow_helper28_common` | |
| `rule_CARE_ID_Std` (CRE) | `fn_snow_helper37_common` | special characters removed; never raises an exception |
| `mplt_Global_Addr_Validation` (+ `rule_Addr_Line_*`) | `fn_snow_helper34_common` (steps 29-33) | pass-through validator, see below |
| `mplt_DST_Correction` (TIMELINE) | `fn_snow_helper35_common` + `fn_snow_helper47_common` | |
| `mplt_Member_Pty_Rle_Phn_Normalization` (TRS) | `fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` + SQL | |
| `mplt_TRS_Pty_Rle_Alt_Id_Normalization` (TRS) | `fn_snow_helper01_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` + SQL | |
| `mplt_Member_Pty_Rle_Phn_Consolidation`, `..._EAddr_Consolidation`, `..._Rel_Consolidation`, `mplt_Pty_Rle_Rel_Timeline_Validation` | inlined SQL | set-level mapplets (many rows in, fewer or more out) |

The full list of shared functions, with what each one does, is the table at the top of each `common/` file.

### How a mapplet is split

A mapplet usually mixes **logic** (cleaning, rules) with **lookups** (code values, exception catalogue, junk names,
area codes). In Snowflake the two are written differently, for speed and because of a Snowflake limit:

- **Logic** is a pure SQL UDF. Snowflake inlines SQL UDFs into the query, so they run vectorised at the speed of the
  expression itself. Multi-output mapplets return an `OBJECT`, read as `obj:attribute::TYPE`.
- **Lookups** are table functions without arguments (`fn_snow_helper40..47_common`) that return one row per lookup key
  (IDQ "return any row"). The procedure `LEFT JOIN`s them on the lookup condition and passes the result into the logic
  UDF. That is one hash join per lookup instead of one query per row, and it avoids correlated subqueries inside UDFs,
  which Snowflake supports only in `WHERE` clauses.

### Why no Java UDFs

Every rule is string or regular-expression work that Snowflake SQL does natively. Java UDFs would move each batch of
rows into a JVM and back, with no gain, and would be slower than the inlined SQL. The one piece that cannot be written
in SQL, the AddressDoctor call, is a remote service, not a computation; a Java UDF would not help there either (see
below). So the port has no Java UDFs.

### Address validation

`dq_Global_AddressValidation_Hybrid` is Informatica AddressDoctor, a licensed service that Snowflake does not have.
`fn_snow_helper34_common` is the **pass-through validator** (the same choice as the Java port's
`PassThroughAddressValidator`): every expression of the mapplet runs (suite stripping, pre-scrub, post-scrub, state and
county FIPS, zip split, 0 geocodes), and the prepared input stands in for the service result. AddressDoctor-only
outputs (match code, mailability score, CASS / DPV, building parts) are NULL, so every address with a known type
scores `'100'`.

To validate for real, replace `fn_snow_helper34_common` with a function of the same signature and keys that calls an
address service through a Snowflake **external function** (or a Marketplace / Native App address service). No
procedure has to change.

## Snowflake semantics the port depends on

These differ from Oracle, and some from IDQ. Each is handled in the code and called out where it matters:

| Topic | Snowflake | What the port does |
|---|---|---|
| Empty string | `''` is **not** NULL (as in IDQ; Oracle treats it as NULL) | the IDQ blank test `LENGTH(RTRIM(x)) = 0 OR ISNULL(x)` is `fn_snow_helper03_common` |
| Concatenation | `'a' \|\| NULL` is **NULL** (IDQ and Oracle give `'a'`) | every nullable operand of a key is wrapped in `NVL(x, '')` |
| `CHAR` padding | no blank-padded comparison | `TRIM(ROWID_SYSTEM) = '<SRC>'` on the MDM cross-reference tables |
| Unique / primary keys | **not enforced** (except on hybrid tables) | emulated, see the next section |
| Multi-table insert | `VALUES` may only name columns of the query | every value is computed as a named column first |
| Static lookup cache | one statement reads one snapshot | each mapping is one `INSERT ALL`, so lookups on tables it writes see the pre-run state |
| Transactions | explicit `BEGIN TRANSACTION` in the procedure | `COMMIT` at the end, `ROLLBACK` and re-raise on any error |

### Unique keys (BAD DATA)

In Oracle the targets have unique keys, and IDQ relies on them: a duplicate row is **rejected by the database and the
session carries on**. Snowflake does not enforce `UNIQUE` / `PRIMARY KEY`, so without help the duplicates would be
loaded. Every procedure therefore applies the keys itself:

| Table | Key |
|---|---|
| every `C_S_*` target | `PKEY_SRC_OBJECT, VERSION_SEQ` |
| `EXC_STG_BAD_REC_MEMB` | `SRC_SYS, SRC_SYS_ID_1..3, EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE` |
| `STG_TRS_VALID_MEMBERS` | `PTY_PK` |
| `STG_TRS_DEACTIVED_MEMBERS` | `INDV_ID` |
| `STG_TRS_D_UNQ_ADDR` | `ADDR_ID` |
| `STG_ECI_D_MEDICAID` | `ID_MEDICAID` |

A row is written only when it is the first row of its key in this run (`ROW_NUMBER() ... = 1`, `uq_*` columns) and
its key is not in the table yet. Two consequences worth knowing:

- IDQ keeps whichever duplicate arrives first, which is not defined; the procedures keep a fixed one (usually the
  latest), as noted in each header.
- IDQ truncates most targets before loading, this port does not (insert only). A second load of the same keys
  therefore adds nothing instead of duplicating rows. To get IDQ's full reload, empty the targets outside this code
  base first (parking note 002, D11).
- `RUN_DATE` is the run start, so exception keys normally cannot repeat across runs. The exception is the ECI SSN row,
  whose `RUN_DATE` is not linked in IDQ: its key repeats, and Oracle rejects it on every later run. The procedure
  reproduces that (an invalid SSN is logged once, ever).

## Prerequisites

The procedures run in one database and schema that hold, or can see unqualified, the same tables as the IDQ
connections (STAGING, the MDM ORS and the reference tables):

- staging sources and targets (`STG_*`, `C_S_*`, `EXC_STG_BAD_REC_MEMB`, `DQM_ADDRESS`, the `V_*` views);
- MDM hub tables read by lookups: `C_B_PTY_XREF`, `C_B_PTY_RLE_ALT_ID`, `C_B_PTY_RLE_ALT_ID_XREF`,
  `C_B_PTY_RLE_REL_XREF`, `C_B_PTY_HMRG` (CRE merge history);
- reference tables: `V_LOOKUP_CODE_VALUE`, `LOOKUP_CODE_VALUE`, `EXC_LOOKUP_CODE_VALUE`, `REF_JUNK_NAME_LIST`,
  `REF_MATCHCODE_DESC` (IDQ `ref_MatchCode_Desc`), `REF_DYLGHT_SVNGS_TM`, `STG_TRS_CD_REF`;
- `RDM.REF_PHN_AREA_CD`, schema-qualified as the IDQ `Snowflake_PEI` lookup reads it (edit
  `fn_snow_helper44_common` if it lives elsewhere).

Oracle `DATE` columns are expected as `TIMESTAMP_NTZ` (they carry a time). Create `VARCHAR` columns **without a
length** (`VARCHAR` = 16 MB, no storage or speed cost in Snowflake): a value longer than a declared length fails the
whole statement in Snowflake, while IDQ cut it to the port precision row by row.

## Install

```sh
cd idq-to-snowflake
snowsql -c <connection> -d <database> -s <schema> -f install.sql
```

[install.sql](install.sql) creates, in order, the shared functions (`common/01`), the lookup functions (`common/02`),
the mapping helpers and every procedure, workflow by workflow, and lists what it installed. A SQL UDF is validated when
it is created, so the referenced tables must exist first. `CREATE OR REPLACE` replaces only these functions and
procedures.

## Run

Run a whole workflow with `snowsql -f <workflow>/run_<workflow>.sql`, or one procedure with
`CALL sp_snow_main_m_Tgt_C_S_ECI_Pty();`. Each procedure returns its run log line (mapping, step, rows). The run
scripts follow the taskflow order of `docs-from-idq-exports/<workflow>/taskflow.md`; parallel IDQ paths run one after another, keeping
every dependency. The IDQ command task (`touch <workflow>.ind`) is left to the scheduler. A Snowflake task graph
(`CREATE TASK ... AFTER ...`) can replace the script one procedure per task.

From the CLI: start with `-Detl_process=SNOWFLAKE_SP -Dmock_snowflake_sp=false` and use `run-etl`. `SnowflakeSpRunner`
reads the `CALL` lines of the run script (folder `idq.snowflake-sp.dir`, default `idq-to-snowflake`) and calls each
procedure over the Snowflake JDBC driver in that order, stopping at the first failure. The connection comes from the
environment: `SNOWFLAKE_JDBC_URL`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`. Keep each run script to one
`CALL sp_snow_main_<mapping>();` per line without arguments.

## How a mapping becomes a procedure

| IDQ | Snowflake |
|---|---|
| Mapping | `sp_snow_main_<mapping>`, `LANGUAGE SQL`, `EXECUTE AS CALLER`, returns the run log |
| User parameter `$Name` | procedure argument `P_NAME` with the IDQ default |
| `$sys.MappingRunStartTime`, `SYSTIMESTAMP()`, `SYSDATE` | `l_run_ts`, taken once at the start |
| Target option *Truncate target table* | **not performed**, marked |
| Source with custom SQL | the SQL copied into a CTE (a stored filter next to custom SQL is ignored, as IDQ does) |
| Expression, Filter, Joiner | SQL expressions, `WHERE`, joins |
| Lookup on reference data | `LEFT JOIN` to a lookup table function |
| Lookup on a table the run also writes | a `LEFT JOIN` / `NOT EXISTS` inside the same statement (one snapshot) |
| Mapplet / rule | a `fn_snow_helperNN_common` call |
| Router with several groups | one `INSERT ALL` with a `WHEN` per group; a row goes to every group it matches |
| Sorter (distinct) | `DISTINCT` |
| Aggregator without aggregate functions | `ROW_NUMBER()` picking the last row in IDQ sort order (NULL high) |
| Normalizer | a lateral table function or `UNION ALL` |
| Update strategy `DD_DELETE` | **not performed**, marked |
| Target port with no link | explicit `NULL` |

## IDQ behaviour carried over on purpose

The same list as the Oracle port, plus what Snowflake makes visible:

- `m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` writes no rows (the filter tests the source key);
  `P_TEST_LOOKUP_RESULT => 'Y'` gives the intended behaviour.
- `m_Tgt_C_S_FSS_Pty_Validation` writes the *Reactivation* row into the status table.
- Exception rows write the looked-up code where the mapping does (NULL when not configured).
- Port precision: values are cut where an IDQ port is shorter than the data: the gender mapplet reads one character,
  the phone rule keeps ten (which also drops the extension appended to TRS work phones), Medicaid / member ids ten.
- In the TRS phone normalizer the phone rule gets only the number (its source system and usage inputs are not linked),
  so the toll-free check for main numbers never runs for TRS.

## Open risks

- **Not compiled or run** (see the top). Expect small dialect fixes on first install.
- **Port-precision truncation** (gender, phone, ids) follows the IDQ rule that a value is cut to the precision of the
  port it enters. Confirm on IDQ with an 11-digit phone and a `'MALE'` gender.
- **`mplt_Date_Greater_Than_Fifty_Years`** compares the year difference as text, so end dates 6 to 10 years ahead also
  become NULL. Reproduced; confirm with IDQ and decide whether to fix (docs/common_insights.md 1.15).
- **Address validation** is a pass-through until an address service is plugged in.
- **Unique-key emulation** keeps one fixed row per key where IDQ keeps the first that arrives.
- **Insert only**: no truncate, so the targets must be emptied outside this code base to reproduce a full reload.
