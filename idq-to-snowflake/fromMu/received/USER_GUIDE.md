# TRS Compare — User Guide (v5.4.0)

*Copy Oracle IDQ data to Snowflake, run the Snowflake ETL, and bump
its results against the daily IDQ ETL results — by domain, by
dimension, and by spine.*

**Snowflake layout.** Snowflake is organised by SOURCE, not by
Oracle layer. Oracle organises by layer — LANDING, STAGING,
HHS_MDM — but in Snowflake a table's destination is its source,
never its Oracle layer. For this project the source is TRS:

| Oracle example | Oracle layer | Snowflake destination |
|---|---|---|
| `C_S_TRS_PTY` (and all `C_S_*`) | HHS_MDM | `MDM_ETL_TRS.TRS_ETL_WRK`, as a target table (see discriminator below) |
| `EXC_STG_BAD_REC_MEMB` | STAGING | `MDM_ETL_TRS.TRS_ETL_WRK`, as a target table |
| `LDG_TRS_CV_DC_MCI_ALIAS` (example only — not in the current catalog) | LANDING | If it were added to the catalog as an input, it would go to `MDM_ETL_TRS.TRS_ETL_WRK` — not to a LANDING schema in Snowflake, because Snowflake has no LANDING schema in this design |
| Any TRS input (STAGING sources, HHS_MDM `C_B_*`, lookups) | STAGING / HHS_MDM | `MDM_ETL_TRS.TRS_ETL_WRK`, as an input table (no discriminator) |
| `REF_PHN_AREA_CD` | RDM (Oracle) | `MDM_ETL_TRS.TRS_ETL_WRK`, as an input table |

All TRS tables, views, stored procedures and functions live in
`MDM_ETL_TRS.TRS_ETL_WRK` — one database per source, one schema in
it.

**Why the schema name carries the source.** You are right that
a bare `ETL_WRK.C_S_TRS_PTY` does not say which source it
belongs to — TRS, ECI, WIC, or any other. The database alone
does not fix that in practice, because the DDL file, a log
line, a copied query, or a `USE SCHEMA` session does not show
the database: the name you actually read is the schema-qualified
one. So the schema is named `<SOURCE>_ETL_WRK` —
`TRS_ETL_WRK` here, `ECI_ETL_WRK`, `WIC_ETL_WRK`, and so on for
future sources, derived from `SNOWFLAKE_SOURCE` unless you
override it. The idiomatic, fully qualified reference is then
three-part — `MDM_ETL_TRS.TRS_ETL_WRK.C_S_TRS_PTY` — and the
two-part form in the DDL file, `TRS_ETL_WRK.C_S_TRS_PTY`, is
already unambiguous on its own. The source appearing in both
the database and the schema is intentional redundancy, not a
typo: the database is the namespace, the schema is the
self-describing name a reader actually sees. Use the
three-part form in any cross-source query (for example, a
COMMON function referring to a TRS table); use the two-part
form in the DDL file, which is applied after
`USE DATABASE MDM_ETL_TRS`, so it stays portable across
environments that use different database names. Future sources (ECI, WIC, TTF, CRE, FSS) each get their own
database (`MDM_ETL_ECI`, …) and their own catalog, and share
`MDM_ETL_COMMON` (below). One API instance serves one source,
because the catalog is source-specific.

**Scope note on Provider.** The Provider domain is out of
scope for this project: these workflows do not load Provider
parties, and no Provider tables belong in this catalog. A
Provider source (for example a future C21 source) may come
later, as its own source with its own catalog — it is not an
example for this guide, and its tables must not be added here.

**Discriminator (pivotal) column.** Every target table in
`TRS_ETL_WRK` carries `DATA_SOURCE VARCHAR(20) NOT NULL DEFAULT
'SNOWFLAKE'` as its last column. The copy writes IDQ rows with
`DATA_SOURCE='IDQ'`; the Snowflake ETL writes its rows with
`DATA_SOURCE='SNOWFLAKE'`. The same physical table therefore
holds both the expected and the actual data, and the compare
filters on `DATA_SOURCE` instead of comparing two schemas:
`WHERE DATA_SOURCE='IDQ'` vs `WHERE DATA_SOURCE='SNOWFLAKE'`.

Two consequences worth stating plainly. (1) The copy truncates
the whole target table (both sides) before loading IDQ rows, and
the ETL step deletes only `DATA_SOURCE='SNOWFLAKE'` rows before
calling the runners — a DELETE by discriminator, never a
TRUNCATE, so IDQ rows survive the ETL step. Without that
delete, the procedures' insert-only guards would suppress a
re-run. (2) The `DEFAULT 'SNOWFLAKE'` on the column is
intentional: a procedure that inserts without naming
`DATA_SOURCE` still produces the correct side. Procedures
should set it explicitly anyway.

**What the discriminator is — and is not — on.** It is on
target tables: the IDQ side's tables and the Snowflake side's
tables, which are now the same table. It is not on the Oracle
input tables: those rows are the shared Oracle input, copied
once, and are neither IDQ nor Snowflake data, so a discriminator
on them would carry a single meaningless value.

**COMMON (framework, not a copy destination).** `COMMON` holds
Job Controls, Metrics, and reusable Functions / Stored
Procedures across all sources (date parsing, birth-date
validation, and similar). It is database `MDM_ETL_COMMON`,
schema `COMMON`, configurable with
`SNOWFLAKE_COMMON_DATABASE` / `SNOWFLAKE_COMMON_SCHEMA`. The
job-control table in COMMON is one table with a `SOURCE`
column (`SOURCE='TRS'`, `'ECI'`, …), not one table per source
— the same discriminator philosophy as `DATA_SOURCE`. The
compare API does not copy into COMMON and does not read it;
the ETL procedures write checkpoints there and call its
functions qualified. The phone area-code table is not in
COMMON: it is a TRS input in `TRS_ETL_WRK`, read unqualified from
`TRS_ETL_WRK` like every other helper's table.

**ETL setup (outside this code).** (1) Install all
procedures, functions and views in `MDM_ETL_TRS.TRS_ETL_WRK`.
(2) Every insert into a target table must produce
`DATA_SOURCE='SNOWFLAKE'` — explicitly, or by the column
default. (3) `fn_snow_helper44` reads the phone table
unqualified from `TRS_ETL_WRK`. (4) Job-control writes go to
`MDM_ETL_COMMON.COMMON.JOB_CONTROL_ETL` with `SOURCE='TRS'`
(and the step-story view lives with it), and shared helpers
are called qualified from COMMON.

**About this guide.** It covers the system as it stands: the
design, the daily operator flow, the full API reference, the
complete environment-variable reference, the full table
catalog, deployment and security, and maintainer instructions
for adding a table or workflow. Where a fact depends on your
site (your IdP's token flow, your Snowflake role's exact
grants), the guide says so and tells you how to verify it,
rather than inventing a detail.

**Who this guide is for, and how to use it.** If you are the
morning operator, read §5 (the runbook) and §8 (reading results)
and keep §10 (troubleshooting) open. If you are setting the system
up for the first time, work through §4 in order and tick off §17.
If you are maintaining or extending the code, read §2, §3, §12,
and §13. If you only need one fact, use the table of contents
below — every section is meant to stand alone.

**Contents**

1. Terminology and scope
2. Architecture — schemas, roles, and the data flow
3. How the code is structured
4. Step A — one-time setup (prerequisites, ETL install, DDL, the four missing objects, API install, configuration, SSO, security, smoke test)
5. Step C — the daily operator runbook
6. API reference (every endpoint, request, response, and error)
7. The copy job, in full detail
8. Reading results — copy, ETL, and compare
9. The control store (job history)
10. Troubleshooting
11. Deployment and operations
12. Testing
13. Maintainer guide — adding a table, a workflow, a dimension, a compare
14. Limitations, assumptions, and what this project does not do
15. Frequently asked questions
16. Suggested follow-ups, in priority order
17. Pre-production checklist
Appendix A. Complete table catalog (generated from the code)
Appendix B. Complete configuration reference

---

## 1. Terminology and scope

**Domain is the parent. Dimension is a slice within a domain.**
You proposed this terminology and the code adopts it verbatim.
Examples: Domain `Member`, Dimensions `Demographics`, `Phones`,
`Emails`, `Alternate IDs`, `Addresses`, `Plans`, `Relationships —
Member to Member`, and so on. Domain `Reference` holds the TOA
catalogue, which is not a Member slice and must not be mistaken
for one.

**Expected vs Actual.** In this guide, IDQ is the *expected* side
(the production system of record) and Snowflake is the *actual*
side (the candidate being bumped against it). The code distinguishes the sides by `DATA_SOURCE` in the same
`TRS_ETL_WRK` table (`'IDQ'` vs `'SNOWFLAKE'`) — but when you present
a compare to a business reader, say
"Expected vs Actual", not "Oracle vs Snowflake". It reads better,
and it survives the day Snowflake becomes production.

**Spine.** A spine is a set of keys that every dimension is
measured against. There are two: the *valid-member spine*
(distinct `INDV_ID` in `STG_TRS_VALID_MEMBERS`) and the
*party-role spine* (distinct `PKEY_SRC_OBJECT` in
`C_S_TRS_PTY_RLE`, of the form `INDV_ID|Member` for Member
parties). If a spine differs, downstream dimensions will differ
too — fix the spine first. See §8.

**PKEY.** `PKEY_SRC_OBJECT` is the primary-key source object on
every `C_S_*` table: the business key of a party or party-role row,
in the form `INDV_ID|Member` (or with a role suffix for role
tables). The compare's key set for a dimension is the set of its
PKEYs, or its natural key where it has no PKEY (see Appendix A).

**Scope, stated plainly.** Only the **Member** domain is in scope.
These two workflows do not load Provider parties: PCP relationships
reference providers by TPI only, so there is no Provider dimension
list yet. Adding one is a catalog change (Appendix A, §13), not a
code change. The four deactivation workflows (Initial /
Relationship / History / Complete) are also out of scope: they were
not in the Snowflake procedure zip, so their runners are not called
here. Note the nuance: two *deactivation capture* tables
(`STG_TRS_DEACTIVED_MEMBERS`, `STG_TRS_DEACTIVATED_RELATIONSHIPS`)
*are* in the expected catalog, because the Ongoing workflow writes
them — capture tables are in scope, deactivation execution is not.

---

## 2. Architecture — schemas, roles, and the data flow

```
Oracle (production, after the daily IDQ run)
  STAGING.*  ──┐
  HHS_MDM.*  ──┼──►  FastAPI POST /runs/copy  ──►  Snowflake TRS_ETL_WRK   (inputs, archive)
  RDM.*      ──┘                                   Snowflake TRS_ETL_WRK   (IDQ targets, expected)
                                                       │
  Snowflake TRS_ETL_WRK  ◄── copy (inputs) ────────────────┘
        │  + empty target tables (DDL only)
        ▼
  POST /runs/etl  →  sp_etl_run_wf_TRS_Stage_Load_TOA
                     sp_etl_run_wf_TRS_Stage_Load_1_Ongoing
        │  (procedures clean their WRK_TRS_* tables at start,
        │   publish in one transaction, leave WRK tables in place)
        ▼
  POST /runs/compare  →  TRS_ETL_WRK, DATA_SOURCE='IDQ' vs 'SNOWFLAKE', by dimension + spine
  GET /runs[/{id}]    →  status, messages, and full summaries, any time
```

| Snowflake container | What is in it | Who writes it | After sql/01 + sql/04 |
|---|---|---|---|
| `MDM_ETL_TRS.TRS_ETL_WRK` — input tables | True Oracle inputs, copied once. The ETL reads them; they carry no discriminator. | Copy job only | 29 tables (26 with DDL + 3 missing shapes) |
| `MDM_ETL_TRS.TRS_ETL_WRK` — target tables | IDQ rows (`DATA_SOURCE='IDQ'`) AND Snowflake rows (`DATA_SOURCE='SNOWFLAKE'`) in the same table. The expected side and the actual side, told apart by the discriminator. | Copy job (IDQ side), then the ETL procedures (SNOWFLAKE side) | 19 tables |
| `MDM_ETL_COMMON.COMMON` | Framework only: job control (`JOB_CONTROL_ETL`, with `SOURCE`), metrics, shared functions/procedures. Not a copy destination. | ETL procedures (checkpoints, metrics) | Framework tables/functions, not counted in the 49 |

Counts: the catalog has **30 input specs** and **19 expected
specs** (49 total). Of the 30 inputs, **26 have DDL** in
`sql/01_etl_wrk.sql` and **4 are missing** from the exports
(see §4.4). `sql/01_etl_wrk.sql` holds the 45 present tables
(26 inputs + 19 targets, targets with the `DATA_SOURCE`
column). `sql/04_missing_tables.sql` adds minimal shapes for
all 4 missing inputs in `TRS_ETL_WRK` — hence 29 inputs + 19 targets
= 48 tables in `TRS_ETL_WRK` once both files are applied.

**The trap this layout avoids.** It is tempting to load
SNOWFLAKE rows into a target table before the ETL runs, or to
leave yesterday's SNOWFLAKE rows in place. Do not. The Snowflake
procedures are insert-only with existing-key guards, so
pre-loaded or stale SNOWFLAKE rows would suppress the Snowflake
rows the ETL is supposed to produce, and the compare would then
"pass" for the wrong reason. The SNOWFLAKE side starts empty,
every time: the copy truncates the whole target table, and the
ETL step deletes `DATA_SOURCE='SNOWFLAKE'` rows before calling
the runners. See §7 for the full copy design.

**What the API never does.** It never runs DDL, never drops a
schema, and never writes to Oracle. DDL is a one-time, by-hand
step (§4). Everything the API does after that is `TRUNCATE`,
`INSERT`, `SELECT`, and `CALL`. It also never auto-detects IDQ
completion and never schedules itself — see §14.

**Request flow.** A request enters a thin route
(`app/api/routes.py`), which validates it, calls a service with
the repositories it needs (injected via `Depends` from
`app/api/dependencies.py`), and records the run. The service
(`app/services/`) owns business rules only. The repository
(`app/repositories/`) owns connections and queries. The catalog
(`app/domain/catalog.py`) and explicit table definitions
(`app/domain/tables.py`) are the shared vocabulary. No layer
reaches past its neighbour: routes do not build SQL, services do
not open connections, repositories do not decide verdicts.

---

## 3. How the code is structured

This section is the design record for the code, so a future
maintainer keeps the layering intact.

**Design, in one paragraph.** The structure follows the
simplicity of Spring MVC Rest + Spring Data JDBC, translated
pythonically — not Java in Python. Thin routes, orchestration
services, explicit repositories, named SQL constants imported
by name, and injected dependencies. No ORM, no reflection, no
string-built queries, no derived query names.

**Request flow.** A request enters a thin route
(`app/api/routes.py`), which validates it, calls a service with
the repositories it needs (injected via `Depends` from
`app/api/dependencies.py`), and records the run. The service
(`app/services/`) owns business rules only. The repository
(`app/repositories/`) owns connections and queries. The catalog
(`app/domain/catalog.py`) and explicit table definitions
(`app/domain/tables.py`) are the shared vocabulary. No layer
reaches past its neighbour: routes do not build SQL, services do
not open connections, repositories do not decide verdicts.

- **Repositories** (`app/repositories/`): `OracleRepository`,
  `SnowflakeRepository`, `RunRepository`. Explicit, typed methods
  named for the operations the job needs (`count_rows`,
  `stream_rows`, `key_difference`, `coverage_count`,
  `call_procedure_in_schema`, `delete_discriminator_rows`, …).
  No derived queries (no method-name parsing — that would be a
  mini-ORM), no generic CRUD base class, no ORM session. One
  repository serves all 49 tables, parameterised by an explicit
  `Table` object — not one repository per table.
- **Named SQL constants** (`app/repositories/queries.py`): the
  Spring `sql-named-queries` idea, but as module-level constants
  imported by name, not a `.properties` file looked up by string
  key. A typo is an `ImportError` at startup, and find-usages
  works. The file is deliberately short: only the fixed statements
  with no Core equivalent (`TRUNCATE`, `USE SCHEMA`, `CALL`,
  health `SELECT 1`). Per-table queries stay as Core statements
  in the repositories, because they are dynamic by table, schema,
  and key columns — externalising each as a named query would
  mean 49 copies or a templated string, which is the
  string-templating problem again.
- **Injected dependencies** (`app/api/dependencies.py`): routes
  declare repositories with `Annotated[Repo,
  Depends(get_repo)]`, and services take repositories as
  arguments. Tests replace a provider with
  `app.dependency_overrides` or pass a fake repository straight
  to a service — no monkeypatching of globals. Repositories are
  built from an engine *factory*, not an engine, and only connect
  on first use, so declaring one as a dependency never touches
  its database: a dry-run copy or a plain `/health` works with
  no databases configured.
- **Services are pure orchestration** (`app/services/`): business
  rules only, no SQL, no connections, no engines. That is what
  makes the service tests possible (see §12).
- **Routes are thin**: validate, call a service, record the run,
  return the response. The API-key check is a route-level
  `dependencies=[Depends(...)]`, not a function parameter, because
  a `Depends()` default cannot precede non-default parameters in
  Python — and because auth is a route concern, not an argument.
- **No ORM anywhere.** No SQLModel, no declarative models, no
  session, no automap, no `MetaData.reflect()`. SQLAlchemy Core
  is not an ORM — it is the expression builder under the ORM,
  used here on its own. The code reads like a fluent API
  (`select(...).except_(...)`) without ever creating a model
  class that pretends to *be* a row.
- **Typed models are Pydantic only.** Every API request and
  response is a Pydantic model, so `/docs` shows the contract.
  One model serves as domain object and API shape — no
  Entity/DTO/mapper trio.

**The only `text()` statements left** are `TRUNCATE`, `CALL`,
`USE SCHEMA`, and health `SELECT 1`, because Core has no
equivalent for them. They take schema/table/procedure names from
the catalog and workflow allowlists only, never from a request
body. If you grep the project for `text(`, that short list is
all you will find.

---

## 4. Step A — one-time setup

Work through this section in order. Do not skip §4.4: the copy
will report `PARTIAL` and the ETL will fail on lookups until the
four missing objects are dealt with.

### 4.1 Prerequisites

- **Python 3.11 or later.** The project uses `X | None` type
  syntax and `datetime.now(timezone.utc)` throughout; older
  Python will fail at import, not at runtime.
- **Network access** from the API host to: Oracle (host:port from
  `.env`, default 1521) and Snowflake (account from `.env`).
  No Oracle client installation is needed: the Oracle driver is
  `oracledb` in thin mode.
- **Accounts.** An Oracle user with `SELECT` on `STAGING`,
  `HHS_MDM`, and `RDM` (read-only is enough — the API never writes
  to Oracle). A Snowflake user/role for the comparison database
  (see §4.7 for the privileges to verify — TRUNCATE is the most
  privileged operation and the one most likely to fail on a
  least-privilege role, so verify it before the first run rather
  than assuming it).
- **The Snowflake ETL package** (the simplified modular rewrite,
  delivered separately as
  `TRS_Snowflake_Modular_Rewrite_Simplified.zip`): framework,
  mapping procedures, and runners. This project does not contain
  those procedures; it only calls them.
- **Your Oracle exports**, if you need to regenerate DDL or table
  definitions (see §13). The DDL and table definitions in this
  project were generated from the exports dated 2026-10-16.

### 4.2 Install the Snowflake ETL in TRS_ETL_WRK

The procedures are the simplified modular rewrite (no step-level
resume; each procedure cleans its own `WRK_TRS_*` tables at its
start, runs every step fresh, publishes in one transaction, and
leaves its work tables in place until the next run). Install them
into the `TRS_ETL_WRK` schema, in this order:

1. Your helper functions: TRS-specific helpers into `TRS_ETL_WRK`;
   shared helpers (date parsing, birth-date validation, and
   similar, reusable across sources) into
   `MDM_ETL_COMMON.COMMON`, called qualified from the TRS
   procedures.
2. The framework: `JOB_CONTROL_ETL` DDL (in COMMON, with a `SOURCE` column) + control procedures
   (`sp_etl_job_begin`, `sp_etl_checkpoint`, `sp_etl_job_finish`,
   `sp_etl_job_fail`) — from the simplified package's
   `01_framework/`.
3. The 15 mapping procedures — from the simplified package's
   `02_mappings/`.
4. The two workflow runners — from the simplified package's
   `03_runners/`.

Because the procedures use unqualified table names, they resolve
to the schema they are called from. The API issues `USE SCHEMA
TRS_ETL_WRK` on the same connection before each `CALL`, so that is
where they must live. Do not install a second copy in another
schema and expect the API to find it.

**Verify the install before the API ever calls it.** In a
Snowflake worksheet, as the same role the API will use:

```sql
USE SCHEMA TRS_ETL_WRK;
SHOW PROCEDURES LIKE 'sp_etl_run_%';
-- Expect: sp_etl_run_wf_TRS_Stage_Load_TOA,
--         sp_etl_run_wf_TRS_Stage_Load_1_Ongoing
USE SCHEMA MDM_ETL_COMMON.COMMON;
SHOW TABLES LIKE 'JOB_CONTROL_ETL';  -- with SOURCE='TRS'
SHOW VIEWS LIKE 'VW_ETL_JOB_STORY';
```

Then run the TOA runner once by hand, successfully, before the
API calls it (see §4.8 and the ETL package's own guide §11: the
rewrite still needs its compile check and row-count parity run
against a non-production database first — that requirement is
not removed by this project).

### 4.3 Apply the translated DDL (this project, `sql/`)

The DDL was generated from your Oracle exports by
`scripts/generate_snowflake_ddl.py` (re-run it when a fresh
export arrives; it overwrites `01_`–`03_` but never `04_` — see
§13 for the regeneration procedure):

```sql
-- In a Snowflake worksheet, or with snowsql -f, in this order:
CREATE DATABASE IF NOT EXISTS MDM_ETL_TRS;
CREATE SCHEMA IF NOT EXISTS MDM_ETL_TRS.TRS_ETL_WRK;
CREATE DATABASE IF NOT EXISTS MDM_ETL_COMMON;
CREATE SCHEMA IF NOT EXISTS MDM_ETL_COMMON.COMMON;
```

Then apply, in order:

| File | What it creates | Count |
|---|---|---|
| `sql/01_etl_wrk.sql` | All present tables in `TRS_ETL_WRK`: 26 inputs (no discriminator) + 19 targets (with `DATA_SOURCE`) | 45 |
| `sql/04_missing_tables.sql` | Minimal shapes for the 4 missing inputs in `TRS_ETL_WRK` — **see §4.4 first** | 4 objects |

**Type mapping** (documented in the generator script):
`VARCHAR2(n BYTE|CHAR)` → `VARCHAR(n)`, `CHAR` → `CHAR`,
`NUMBER(p,s)` → `NUMBER(p,s)`, `NUMBER(*,0)` and bare `NUMBER`
→ `NUMBER(38,0)` (every bare `NUMBER` in the needed tables is
an integer ID, sequence, or flag — verified by inspection),
`DATE` → `DATE`, `TIMESTAMP(n)` → `TIMESTAMP_NTZ(n)`,
`DEFAULT sysdate` / `CURRENT_TIMESTAMP` → `DEFAULT
CURRENT_TIMESTAMP()`, literal defaults kept. Grants,
tablespaces, and storage clauses are dropped.

Two notes that matter. First, **byte vs character**: Oracle
`VARCHAR2(50 BYTE)` holds 50 bytes, which can be fewer than 50
characters for multibyte data; Snowflake `VARCHAR(50)` holds 50
characters. The translation is therefore *wider*, not narrower —
it will not truncate multibyte values, but it also does not
reproduce Oracle's byte limit. If you need byte-exact semantics,
that is a separate, deliberate decision, not something to
discover during a compare. Second, **no PRIMARY KEYs are created
on purpose** — the ETL is insert-only and the compare is by key
sets, not by enforced keys. Add PKs later, after the parity run,
if you want them; adding them first would change ETL failure
behaviour on duplicate inserts.

**What was deliberately not translated.** The exports contain
633 tables across the four files (including `BAK_*` backups, TTF
tables, and other domains). Only the 45 present tables the ETL
reads or writes are in `01_etl_wrk.sql`. Translating the rest would
be noise, and it would imply a scope this project does not have.

**Verify the DDL.** After applying, spot-check counts and a
column list in each schema (the numbers must match §2):

```sql
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'MDM_ETL_TRS' AND TABLE_SCHEMA = 'TRS_ETL_WRK';
-- Expect, after sql/01 + sql/04: 48 tables (29 inputs + 19 targets)
```

### 4.4 The four missing objects — do this before the first copy

The supplied Oracle exports contain **no views at all**, and
they do not contain these four objects, even though the Snowflake
ETL reads them through its lookup functions:

| Object | Used by | Columns the procedures actually query |
|---|---|---|
| `V_LOOKUP_CODE_VALUE` (view) | `fn_snow_helper41/42` — code translation | `CODE_TYPE, SRC_SYS, SRC_CODE_VALUE, MSTR_CODE_VALUE` |
| `REF_JUNK_NAME_LIST` | `fn_snow_helper43` — junk-name check | `NAME, EDIT_LIMITATION` |
| `REF_MATCHCODE_DESC` | `fn_snow_helper46` — AddressDoctor match-code text | `MATCH_CODE, DESCRIPTION` |
| `RDM.REF_PHN_AREA_CD` | `fn_snow_helper44` — phone area-code check | `NPA_ID, SERVICE, IN_SERVICE, IN_SERVICE_DT, COUNTRY` |

`sql/04_missing_tables.sql` contains minimal shapes built from
exactly those columns, so the procedures compile and run. **That
file is not a substitute for the real definitions.** Before the
first copy run:

1. Get the real Oracle definition for each object
   (`DBMS_METADATA.GET_DDL`, or a fresh export that includes
   them). For the first three, confirm the Oracle schema — the
   exports do not say, and the catalog records it as unknown.
   Do not guess it in production; the 04 file notes STAGING as
   the most likely candidate for the lookup view, explicitly
   marked as unconfirmed.
2. Translate it with the same rules as the generator, and apply
   it to `TRS_ETL_WRK` (all four, including the phone table, which
   in v5 is read unqualified from `TRS_ETL_WRK` — replacing the
   minimal shapes.
3. Update `app/domain/catalog.py`: set the real
   `oracle_schema` and `missing_from_exports=False` for each
   object. Then **regenerate `app/domain/tables.py`** with
   `scripts/generate_tables.py` (see §13) and re-apply the DDL.
   Step 3 is mandatory, not optional: the copy selects only
   the columns listed in `tables.py`, so if the real Oracle
   object has *more* columns than the minimal shape, those
   extra columns are silently *not* copied until `tables.py`
   is regenerated.

Until you do all three steps, the copy endpoint will report
those four tables as `SKIPPED_MISSING` and the run as `PARTIAL`
— which is the intended behaviour, not a bug: it tells you what
is blocked instead of silently copying 45 tables and letting
the ETL fail later on a lookup.

### 4.5 Install and configure the API

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then fill it in (see §4.6 and Appendix B)
uvicorn app.main:app --host 127.0.0.1 --port 8000
# Docs: http://localhost:8000/docs -- Swagger UI, served locally
# from the swagger-ui-bundle package (installed by
# requirements.txt).  No CDN is involved: the page's JS/CSS come
# from this server at /swagger-static, so /docs works on a
# network that blocks external CDNs and on an offline machine.
# If API_KEY is set, click Authorize in Swagger UI and enter
# the key once -- it is sent as the X-API-Key header on every
# try-it-out request.  With no API_KEY set, no header is needed.
# Production note: --reload is for development only. Never use it
# in production; it restarts the server on file changes. See §11.
```

Alternatively, install the project itself (so `uvicorn
app.main:app` works from anywhere in the venv):

```bash
pip install -e .
```

### 4.6 Configuration — complete reference

Every setting lives in `.env` (see Appendix B for the full table
with defaults and whether each is required). The essentials:

- `ORACLE_HOST / PORT / SERVICE / USER / PASSWORD` — one user
  with `SELECT` on `STAGING`, `HHS_MDM`, and `RDM`. Use a
  read-only user; the API never writes to Oracle, so it should
  never need more. Defaults: host `localhost`, port `1521`,
  service `ORCL` — change all three for production; the defaults
  are local-development placeholders, not guesses about your
  site.
- `SNOWFLAKE_ACCOUNT / USER / DATABASE` (default database
  `MDM_ETL_TRS`, derived from `SNOWFLAKE_SOURCE`), plus the
  schema name if yours differs from `TRS_ETL_WRK`, plus
  `SNOWFLAKE_WAREHOUSE` and `SNOWFLAKE_ROLE` if your site
  requires them. **Warehouse note:** if you leave
  `SNOWFLAKE_WAREHOUSE` empty, Snowflake uses the default
  warehouse for the user/role. If that user/role has no default
  warehouse, every Snowflake query fails with a warehouse error
  — that is a configuration error, not a code error, and it is
  the first thing to check if all Snowflake calls fail at once.
- `API_KEY` — if set, every endpoint except `/health` requires
  the `X-API-Key` header. Set it for any shared deployment;
  leave it empty only for local development.
- `CONTROL_DB_URL` — default `sqlite:///./trs_compare.db`
  (a file named `trs_compare.db` in the working directory).
  Change it if you run the API from a different directory than
  you expect, or the run history will appear to "disappear"
  (it is just in a different file).
- `COPY_BATCH_SIZE` (default 5000) and
  `COMPARE_SAMPLE_LIMIT` (default 20). The sample limit in a
  request overrides the setting for that request, bounded to
  0–200 by the request model.

**Never commit a real `.env`.** The `.env.example` file is the
template; your filled-in `.env` contains passwords and tokens
and must stay out of version control. If it is ever committed,
rotate the credentials — deleting the file from history is not
enough.

### 4.7 Authentication — Snowflake SSO, in plain terms

There are three supported modes, chosen by
`SNOWFLAKE_AUTHENTICATOR`:

| Mode | When to use it | How it works |
|---|---|---|
| `externalbrowser` | Local, interactive runs only | The Snowflake connector opens a browser window for your SSO login. It cannot work on an unattended server — there is no browser there to click through. If a server run "hangs" at the first Snowflake call, this is almost always the cause. |
| `oauth` | **The API server mode — use this in production** | You obtain an OAuth access token from your identity provider (the same SSO your organisation uses for Snowflake), put it in `SNOWFLAKE_OAUTH_TOKEN`, and the API presents it to Snowflake. The token is never logged or returned by any endpoint. Tokens expire: refresh it through your IdP's normal flow and restart (or reload) the API with the new token. |
| `snowflake` | Fallback, or a dedicated service user | Username + password (`SNOWFLAKE_PASSWORD`). Simplest, but it is not SSO, so use it only if your site allows a service account for this job. |

If you are unsure which your site uses, ask for "the OAuth
token flow for Snowflake" — do not paste a password into a
ticket to get it. The API itself does not implement an OAuth
login flow; it consumes a token you supply, which keeps the SSO
boundary where it belongs (your IdP), not in this codebase.

**Token expiry, and why it is hard to spot.** Engines are lazy
and repositories connect only on first use, so a bad or expired
token does *not* fail at startup. The API starts fine, `/health`
(without `?check_db=true`) reports `ok`, and the first real copy
or compare fails with a Snowflake authentication error. That is
by design (lazy construction is what makes dry runs and plain
health checks work without databases), but it means: after any
token rotation, run `GET /health?check_db=true` before the
morning copy, and treat a Snowflake auth error on the first call
of the day as "token expired" until proven otherwise.

**API-key authentication (separate from Snowflake SSO).** The
`API_KEY` / `X-API-Key` header protects the API itself; Snowflake
SSO is how the API authenticates *to Snowflake*. They are two
different boundaries. Setting one does not set the other.

**Least privilege, to verify with your DBA (not assumed here).**
Oracle: `SELECT` on `STAGING`, `HHS_MDM`, `RDM` only. Snowflake:
`USAGE` on the database and the four schemas, plus whatever
privileges your site requires for `SELECT`, `INSERT`, and
`TRUNCATE` on the comparison tables and `EXECUTE`/`USAGE` on
the ETL procedures. Verify `TRUNCATE` explicitly — it is the
operation most likely to be missing from a least-privilege role,
and a missing `TRUNCATE` privilege fails the copy on the first
table, which at least fails loudly and early. Do not grant the
API role ownership of production schemas; the comparison schemas
are its own, separate database by design.

### 4.8 Smoke test (no databases needed, then with databases)

```bash
pytest tests/ -q
# 47 tests: catalog validation, explicit table definitions,
# fluent query building (EXCEPT / count, compiled without a
# database), dry-run copy plan, health, run history,
# run-repository round-trip, and service tests with fake
# repositories: copy destinations and the discriminator model
# (copy loads IDQ rows only, ETL clears only the SNOWFLAKE side),
# compare MATCH / MISMATCH / PARTIAL verdicts, ETL order,
# parsing, and failure handling -- all without Oracle
# or Snowflake.
curl http://localhost:8000/health
# Plain health touches only the run store: safe for a load balancer.
curl "http://localhost:8000/health?check_db=true"
# Runs SELECT 1 on Oracle and Snowflake separately and reports each
# result; a failure in one does not hide the other.
curl -X POST http://localhost:8000/runs/copy -H 'Content-Type: application/json' \
  -d '{"dry_run": true}'
# Returns the full copy plan (tables, roles, destinations) with
# status PLANNED and copies nothing. Use it before every real run
# if you want to check the table list first, and after any catalog
# change to confirm the plan changed as expected.
```

If the smoke test passes but `?check_db=true` fails on one
database, fix that database's configuration before any copy —
the API will not work around a bad connection, and a copy that
starts with one database unreachable will record per-table
`FAILED` rows for every table it attempts.

---

## 5. Step C — the daily operator runbook

You check by hand that the production IDQ ETL has completed.
This project deliberately does **not** auto-detect IDQ
completion: the IDQ scheduler and its completion signal are
yours, and a wrong auto-detection (copying mid-run IDQ targets)
would be worse than a manual check. If you later want
automation, the clean way is a scheduler job that calls these
same endpoints after the IDQ job reports success — the endpoints
do not change. Do not schedule the copy to run while IDQ is
still writing its targets, or the "expected" side will be a
half-finished IDQ run.

**Before you start, every morning (30 seconds):**

```bash
curl "http://localhost:8000/health?check_db=true"
# Expect: status ok, control_db ok, oracle ok, snowflake ok.
# If snowflake is an auth error, suspect an expired OAuth token
# (see §4.7) before suspecting anything else.
```

**Step 1 — Copy: `POST /runs/copy`.** In a terminal that you
leave open (see the synchronous-request note below):

```bash
curl -X POST http://localhost:8000/runs/copy \
  -H 'X-API-Key: <key>' -H 'Content-Type: application/json' -d '{}'
```

- `{}` means all tables, in catalog order (inputs first, then
  expected tables). An empty `tables` list means the same thing
  as omitting it — it does *not* mean "copy nothing". Use
  `dry_run: true` for "copy nothing".
- To copy a subset (for example, after fixing one table's
  definition): `-d '{"tables": ["C_S_TRS_PTY", "C_S_TRS_PTY_RLE"]}'`.
  Unknown names are rejected with HTTP 400 *before* any database
  is touched, and without leaving an orphan RUNNING
  run behind.
- To label a run for later (recorded in the run's message):
  `-d '{"run_label": "2026-10-25 morning, after IDQ rerun"}'`.
- Response: a `RunResponse` with one result per table —
  `oracle_row_count`, `snowflake_row_count` (which must match,
  or that table is `FAILED`), destinations, and a message.
  Overall status is `COMPLETED`, `PARTIAL` (missing tables
  skipped, or some tables failed), or `FAILED`. See §8 for how
  to read each table status.
- **Gate: do not proceed to ETL unless the copy is
  `COMPLETED`, or `PARTIAL` only because of tables you have
  deliberately decided to skip.** In particular, do not proceed
  on a `PARTIAL` caused by the four missing tables — the ETL's
  lookups will fail. Fix the definitions (§4.4), re-run copy,
  then ETL.
- Re-running copy is safe: it truncates each destination first,
  so a second copy over the same day's data gives the same
  result. If a copy fails halfway, re-run the whole copy — do
  not try to copy only the failed tables and then run ETL,
  unless you have checked that every other table's destination
  is from the same day's Oracle state. A mixed-day TRS_ETL_WRK
  (some tables from today, some from yesterday) is a silent
  compare corruption, not a shortcut.

**Synchronous requests — read this before the first long copy.**
All three POST endpoints are *synchronous*: the HTTP request
blocks until the job finishes. There is no background job queue
and no "202 Accepted, poll later" mode. For a large copy, that
means: use a client that does not time out (for example,
`curl --max-time 0` or a terminal session you leave open), and
do not close the terminal and assume the copy continues — if
the client disconnects, the server may stop processing the
request. The run record is created as `RUNNING` at the start,
so you *can* watch progress from a second terminal with
`GET /runs?run_type=copy` while the first terminal blocks — but
the second terminal cannot finish the job for you. If your
copy regularly takes longer than your client's timeout, that is
a deployment problem to solve (longer timeout, or a scheduler
that calls the API with no timeout), not a reason to split the
copy into subsets by hand.

**Concurrency — one copy at a time.** There is no lock in the
code. Two copy runs at the same time will interleave truncates
and inserts into the same Snowflake tables and corrupt each
other's results. Run one copy, one ETL, and one compare at a
time, in order, from one operator terminal. If two operators
might run the job, agree who runs it — the API will not enforce
it for you. See §14.

**Step 2 — Run the Snowflake ETL: `POST /runs/etl`.**

```bash
curl -X POST http://localhost:8000/runs/etl \
  -H 'X-API-Key: <key>' -H 'Content-Type: application/json' -d '{}'
```

- `{}` runs TOA first, then Ongoing (the default `workflows`
  order). To run one only: `-d '{"workflows": ["ongoing"]}'`.
  An unknown workflow name is rejected before any procedure is
  called; an empty workflow list is rejected outright.
- Response: per-workflow status, the Snowflake `JOB_RUN_ID`
  (the workflow-level grouping id you asked to keep), and the
  runners' messages. A failure stops later workflows and is
  reported as `FAILED` with the error — it is still a 200
  response with a status field, so your operator tooling reads
  the *status*, not the HTTP code, to decide what happened.
  See §6 for the HTTP-vs-run-status distinction.
- If ETL fails, look in Snowflake, not in this API, for the
  cause: `SELECT * FROM TRS_ETL_WRK.VW_ETL_JOB_STORY WHERE
  JOB_RUN_ID = '<id>' ORDER BY EVENT_ID;` and the `WRK_TRS_*`
  tables left in `TRS_ETL_WRK` (the simplified ETL leaves them
  there by design — they are the debugging evidence, not
  leftovers to clean up by hand). Fix the cause, then **re-run
  copy first, then ETL** — that is the clean restart. (In v5,
  the ETL step always deletes the SNOWFLAKE side first, so an
  ETL re-run without a fresh copy is safe — it re-produces the
  SNOWFLAKE rows — but it does not refresh the IDQ side or the
  inputs; only a fresh copy does that.)
- Re-running ETL after one copy, without a fresh copy, inserts
  nothing twice (insert-only guards) — but it also does not
  refresh anything, so it is not a restart, it is a no-op with
  extra log rows.
- To record which copy an ETL run is based on:
  `-d '{"copy_run_id": "<copy run id>"}'` — recorded in the
  run's message for the audit trail.

**Step 3 — Compare: `POST /runs/compare`.**

```bash
curl -X POST http://localhost:8000/runs/compare \
  -H 'X-API-Key: <key>' -H 'Content-Type: application/json' -d '{}'
```

- `{}` compares all 19 expected tables, plus the spine section.
- Filter it: `-d '{"dimensions": ["Phones", "Addresses"]}'` or
  `-d '{"domains": ["Member"]}'`. Dimension names are the exact
  strings from `GET /config/tables` (see Appendix A). A filter
  that matches *nothing* is rejected — reporting `MATCH` over
  zero dimensions would be a false pass.
- `sample_limit` (default 20, 0–200) controls how many
  differing keys are included as samples per dimension. `0`
  means "counts only, no samples" — useful for a quick
  verdict when you already know which dimension differs.
- Response: a `CompareResponse` with `verdict` plus one
  `DimensionCompare` per dimension and the spine section (§8).
- To record which copy a compare is based on:
  `-d '{"copy_run_id": "<copy run id>"}'`.

**Step 4 — Status, any time: `GET /runs`, `GET /runs/{run_id}`.**

```bash
curl 'http://localhost:8000/runs?run_type=compare&limit=10'
curl http://localhost:8000/runs/<run_id>
```

Every run — copy, ETL, compare — is recorded in the local run
store with its status, message, and full summary JSON, so
yesterday's compare is still readable after today's copy. See
§9 for the store itself, including how to query it directly
with `sqlite3`.

**End of the morning: what "done" looks like.** Copy
`COMPLETED`, ETL `COMPLETED` (with a `JOB_RUN_ID` you can quote),
compare `MATCH` — or, if `MISMATCH`, a written note of which
dimensions differ, with their sample keys, and what you did
about them (see §8 for the triage order). A `PARTIAL` compare
is not "done": it means something could not be compared at all.

---

## 6. API reference

Base URL: `http://<host>:<port>` (default local: `http://localhost:8000`).
Interactive docs (OpenAPI, generated from the Pydantic models):
`http://<host>:<port>/docs`. OpenAPI JSON:
`http://<host>:<port>/openapi.json`. The API is **unversioned**
— there is no `/v1` prefix. The application version (`5.4.0`)
is in `app/main.py` and in the OpenAPI `info.version` field.

**Docs are served locally, not from a CDN.** FastAPI's default
/docs page loads Swagger UI's JavaScript and CSS from
unpkg/jsdelivr. That fails where external CDNs are blocked, so
this project turns the default docs off (`docs_url=None`, and
`redoc_url=None` — ReDoc is CDN-based too, so there is no
/redoc endpoint) and re-implements /docs in `app/main.py` with
its JS/CSS mounted from the `swagger-ui-bundle` package at
/swagger-static. `pip install -r requirements.txt` includes
that package; without it the app refuses to start with a clear
message saying to install it, rather than silently falling back
to the CDN.

One more bundling gotcha, fixed in `app/main.py`: the bundled
UI is Swagger UI 4.15.5 (the latest `swagger-ui-bundle`
release), which only renders `swagger: "2.0"` and
`openapi: 3.0.n` definitions, while FastAPI generates
`openapi: 3.1.0` by default. Left alone, /docs shows
"Unable to render this definition / The provided definition
does not specify a valid version field" even though the spec
is fine. So `app/main.py` overrides `app.openapi` to emit
`openapi: 3.0.3` (same paths, schemas and security schemes).
If the bundle ever ships Swagger UI 5, that override can be
deleted and FastAPI's default 3.1.0 spec will work as-is.

**Authentication.** If `API_KEY` is set, every endpoint except
`GET /health` requires the header `X-API-Key: <value>` — in
Swagger UI, use the Authorize button for this (the key is
declared as an OpenAPI security scheme, not a plain header,
precisely so try-it-out sends it).
Missing or wrong key → HTTP 401 with
`{"detail": "Missing or incorrect X-API-Key header."}`.
If `API_KEY` is empty, no header is required (local development
only). Snowflake SSO is separate — see §4.7.

**HTTP status vs run status — the distinction that matters.**
A POST endpoint almost always returns HTTP 200, even when the
job it ran failed. That is deliberate: a `FAILED` copy, a
`FAILED` ETL, and a `MISMATCH` compare are all *successful API
calls with a negative answer*, and the answer is in the
response body's `status` (or `verdict` for compare), not in the
HTTP code. Your operator tooling — and any script you write —
must read the body, not just check for 200. HTTP errors are
reserved for API-level problems: 400 (bad request, e.g. unknown
table name or empty filter), 401 (bad/missing API key), 404
(unknown run id), 422 (request body fails Pydantic validation,
e.g. `sample_limit` outside 0–200 — FastAPI's standard
validation error shape), and 500 (an unexpected server error,
which should not happen for a handled job failure).

**Error response shape (FastAPI standard).**

```json
{"detail": "Unknown table: 'NO_SUCH_TABLE'. See GET /config/tables for the allowlist."}
```

For a 422, `detail` is a list of validation errors with
`loc`, `msg`, and `type` — FastAPI's standard shape, documented
at `/docs`.

### GET /sqlite/tables

Read-only inspection of the SQLite harness file (see the
SQLite harness section in §12): every table in the file
configured by `SQLITE_HARNESS_DB_PATH`, with row counts
grouped by `DATA_SOURCE` where the table has that column.
404 when the setting is unset or the file is missing.
Requires the API key.

### GET /health

No API key required. Query parameter: `check_db` (bool, default
`false`).

```json
{
  "status": "ok",
  "control_db": "ok",
  "oracle": "not checked",
  "snowflake": "not checked",
  "message": ""
}
```

With `?check_db=true`, `oracle` and `snowflake` become `ok` or
`error: <Type>: <message>` (one failure does not hide the
other), and `status` becomes `degraded` unless all checked
systems are `ok`. No credentials are ever returned. Note:
without `check_db`, a bad Oracle/Snowflake configuration does
*not* show up here — engines are lazy (see §4.7). Use
`check_db=true` as the morning pre-check, not plain `/health`.

### GET /config/tables

API key required. Returns the whole catalog plus the configured
Snowflake schema names. Use it to get exact dimension names
for compare filters, and to confirm the catalog you are running
against is the one you expect after any change.

```json
{
  "input_tables": [ { "name": "...", "oracle_schema": "...",
    "copy_role": "input", "domain": "...", "dimension": "...",
    "compare_key": [], "missing_from_exports": false }, "..." ],
  "expected_tables": [ { "...": "...", "compare_key": ["PKEY_SRC_OBJECT"] } ],
  "missing_from_oracle_exports": ["REF_JUNK_NAME_LIST", "..."],
  "snowflake_schemas": { "src": "TRS_ETL_WRK", "idq": "TRS_ETL_WRK",
    "work": "TRS_ETL_WRK", "common": "MDM_ETL_COMMON" }
}
```

### POST /runs/copy

API key required. Request body (`CopyRequest`):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `tables` | list of strings, or null | null (= all tables, inputs first, then expected, alphabetical within each group) | Table names to copy. Case-insensitive. An empty list also means "all" — it does not mean "none". Unknown names → HTTP 400, before any database is touched. |
| `dry_run` | bool | `false` | If `true`, return the plan only (tables, Oracle schemas, roles, missing flags) with status `PLANNED` and copy nothing. No databases are touched. |
| `run_label` | string, or null | null | Free-text label, recorded in the run's message. Use it for "after IDQ rerun" notes. |

Response (`RunResponse`): `run_id` (UUID), `run_type`
(`"copy"`), `status` (`COMPLETED` / `PARTIAL` / `FAILED` /
`PLANNED` for a dry run), `message` (one-line summary plus
per-table failure/skip messages), `started_at`,
`finished_at`, `results` (list of `TableCopyResult`, one per
table — see §8), `snowflake_job_run_id` (null for copy).

Example (abridged, illustrative):

```json
{
  "run_id": "c296a5a0-430e-4846-ac11-44f278e259cb",
  "run_type": "copy",
  "status": "PARTIAL",
  "message": "Copy PARTIAL: 45/49 tables copied. REF_JUNK_NAME_LIST: Not in the supplied Oracle exports; definition must be supplied first (sql/04_missing_tables.sql). This table was NOT copied.",
  "started_at": "2026-10-25T19:27:28Z",
  "finished_at": "2026-10-25T19:31:02Z",
  "results": [
    { "table": "C_S_TRS_PTY", "oracle_schema": "HHS_MDM",
      "copy_role": "expected", "status": "COPIED",
      "oracle_row_count": 48102, "snowflake_row_count": 48102,
      "destinations": ["TRS_ETL_WRK", "TRS_ETL_WRK"],
      "message": "Copied 48102 rows to TRS_ETL_WRK with DATA_SOURCE='IDQ'; SNOWFLAKE side is empty until the ETL step fills it." },
    { "table": "REF_JUNK_NAME_LIST", "oracle_schema": null,
      "copy_role": "input", "status": "SKIPPED_MISSING",
      "oracle_row_count": null, "snowflake_row_count": null,
      "destinations": [],
      "message": "Not in the supplied Oracle exports; ..." }
  ],
  "snowflake_job_run_id": null
}
```

Note on `destinations` for expected tables: it lists both
`TRS_ETL_WRK` and `TRS_ETL_WRK` because both were *touched* (IDQ
copied, target table truncated) — but only IDQ received rows. Read the
message, not just the list, if that distinction matters to you.

### POST /runs/etl

API key required. Request body (`EtlRequest`):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `workflows` | list of strings | `["toa", "ongoing"]` | Workflow names, in the order to run them. Allowed: `toa`, `ongoing`. Unknown names are rejected before any procedure is called. An empty list is rejected (since 3.1). |
| `copy_run_id` | string, or null | null | The copy run this ETL is based on, recorded in the run's message. Audit trail only — the API does not verify that the id exists or that its copy succeeded. Check the copy's status yourself before running ETL. |

Response (`RunResponse`): `run_id`, `run_type` (`"etl"`),
`status` (`COMPLETED` / `FAILED`), `message` (per-workflow
statuses joined, e.g. `"toa: COMPLETED; ongoing: COMPLETED"`),
`started_at`, `finished_at`, `results` (list of per-workflow
dicts: `workflow`, `procedure`, `status`, plus
`snowflake_job_run_id` and `message` for completed workflows,
or `NOT_RUN` with "Not started because an earlier workflow
failed" for workflows skipped after a failure), and
`snowflake_job_run_id` (the last workflow's id, or null).

Example (abridged):

```json
{
  "run_id": "...", "run_type": "etl", "status": "COMPLETED",
  "message": "toa: COMPLETED; ongoing: COMPLETED",
  "results": [
    { "workflow": "toa", "procedure": "sp_etl_run_wf_TRS_Stage_Load_TOA",
      "status": "COMPLETED", "snowflake_job_run_id": "abc-123",
      "message": "JOB_RUN_ID=abc-123 ..." },
    { "workflow": "ongoing", "procedure": "sp_etl_run_wf_TRS_Stage_Load_1_Ongoing",
      "status": "COMPLETED", "snowflake_job_run_id": "def-456",
      "message": "JOB_RUN_ID=def-456 ..." }
  ],
  "snowflake_job_run_id": "def-456"
}
```

### POST /runs/compare

API key required. Request body (`CompareRequest`):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `domains` | list of strings, or null | null (= all) | Filter by domain, exact match (e.g. `["Member"]`). |
| `dimensions` | list of strings, or null | null (= all) | Filter by dimension, exact match (e.g. `["Phones", "Addresses"]`). Names come from `GET /config/tables` / Appendix A. |
| `sample_limit` | int | 20, bounded 0–200 (422 outside) | Differing keys included as samples per dimension. `0` = counts only. |
| `copy_run_id` | string, or null | null | The copy run being compared, recorded in the run's message. Audit trail only — not verified. |

Response (`CompareResponse`): `run_id`, `status`
(`COMPLETED` for `MATCH` or `MISMATCH`, `PARTIAL` for an
uncomparable dimension, `FAILED` for a whole-compare failure),
`message`, `started_at`, `finished_at`, `dimensions` (list of
`DimensionCompare` — see §8), `spine` (list of `SpineCompare`
— see §8), and `verdict` (`MATCH` / `MISMATCH` / `PARTIAL` /
`UNKNOWN` only if the response was constructed for a failure
before any comparison ran). A `MISMATCH` is HTTP 200 — see the
HTTP-vs-run-status note above.

### GET /runs

API key required. Query parameters: `run_type` (`copy` /
`etl` / `compare`, optional), `status` (optional), `limit`
(int, default 50). Returns recent runs, newest first, as a list
of `RunResponse`. **There is no pagination beyond `limit`.**
If you need older runs, query the control store directly (§9)
or raise `limit` — there is no `offset` parameter, and asking
for a very large `limit` returns a very large response.

### GET /runs/{run_id}

API key required. Returns one `RunResponse` for that run id,
with its full summary in `results` (for a compare run, `results`
is the summary *dict* `{verdict, dimensions, spine}`). Unknown
id → HTTP 404 with `{"detail": "No run with id '...'"}`.

---

## 7. The copy job, in full detail

This section is the design record for the copy, so the operator
runbook (§5) does not have to carry it. The implementation is
`app/services/copy_service.py` (orchestration) plus
`app/repositories/oracle_repository.py` and
`app/repositories/snowflake_repository.py` (data access).

**Order.** Inputs first (alphabetical), then expected tables
(alphabetical). The order is deterministic and auditable; the
copy itself has no inter-table dependencies, so alphabetical is
fine. A requested subset (`tables`) runs in the order you gave
it, not catalog order — if you copy a subset, you are
responsible for the order you chose.

**Per-table algorithm, exactly.** For each table in order:

1. If `missing_from_exports` is true, record `SKIPPED_MISSING`
   and move on. No database is touched for that table.
2. Count Oracle rows (Core `COUNT(*)` on the explicit table
   definition from `app/domain/tables.py`).
3. For an **input** table: for each destination schema (TRS_ETL_WRK
   and TRS_ETL_WRK, or MDM_ETL_COMMON only for the phone table): truncate the
   destination, then stream Oracle rows in batches
   (`COPY_BATCH_SIZE`, default 5000) and insert each batch with
   executemany, each batch in its own transaction. Then count
   the first destination back.
4. For an **expected** table: truncate TRS_ETL_WRK, stream-copy
   Oracle rows there, count TRS_ETL_WRK back, then truncate the
   TRS_ETL_WRK table of the same name and do *not* copy into it.
5. If the Snowflake count equals the Oracle count, status
   `COPIED`; otherwise `FAILED` with both counts in the message.
   Any exception on a table records `FAILED` with the exception
   type and message, and the run continues to the next table.

**Overall status.** `COMPLETED` only if every table is
`COPIED` (or the internal `RESET_EMPTY`, which is not surfaced
as a table status). `FAILED` if tables failed and none copied.
Otherwise `PARTIAL` — including the missing-tables case. Read
`PARTIAL` as "some tables are fine, some are not", never as a
pass.

**Why streaming and batching.** Oracle rows are never loaded
whole into memory: `stream_rows` yields batches of
`COPY_BATCH_SIZE` rows as dicts, and each batch is inserted and
committed separately. Raise the batch size for throughput, lower
it for memory — but note the tradeoff in the next paragraph.

**Why per-batch transactions, not one transaction per table.**
A single transaction per table would be atomic (a failure
leaves the destination untouched) but would hold a long
transaction for a large table and would fail the whole table on
a single bad batch. Per-batch commits are faster and more
resilient, at the cost of atomicity: a mid-table failure leaves
a *partial* destination. That cost is only acceptable because
of the re-run rule — re-copy truncates first, so a partial
destination is always repaired by a fresh copy, never by
hand-editing rows. Do not run ETL on a partially copied table.

**Why explicit columns, not `SELECT *`.** The Oracle query
selects exactly the columns listed in `app/domain/tables.py`
(checked in, generated from the Oracle DDL). That makes the
copy's column list reviewable and stable — and it means a new
Oracle column is *not* picked up automatically (see §4.4, step
3, and §13). If you want auto-discovery, you are asking for
runtime reflection, which this project deliberately does not
do. The price is a regeneration step when the schema changes;
the benefit is that a schema change is a visible code diff,
not a silent behaviour change on the next copy.

**What the copy does not do.** No DDL, no writes to Oracle, no
incremental/CDC logic, no watermark, no deduplication beyond
what the tables already contain, no transformation of values
(rows are copied as the drivers return them — dates as dates,
numbers as numbers; the only conversion is the driver's own).
If a value looks different in Snowflake, check the driver/type
mapping first (see §10), not the copy logic.

---

## 8. Reading results — copy, ETL, and compare

### 8.1 Copy results

| Table status | What it means | What to do |
|---|---|---|
| `COPIED` | Oracle count = Snowflake count on the relevant side (for expected tables: the `DATA_SOURCE='IDQ'` side in TRS_ETL_WRK). | Nothing. |
| `SKIPPED_MISSING` | Table not in the Oracle exports; not copied. | Fix §4.4, re-run copy. |
| `FAILED` | Per-table error (connection, missing Snowflake table, count mismatch) with the error in `message`. | Fix the named cause, re-run copy (it truncates first, so it is safe). Do not run ETL on a FAILED table's destination — it may be partially loaded (§7). |

Overall `PARTIAL` means "some tables are fine, some are not" —
read the per-table messages, do not treat it as a pass. Overall
`FAILED` (nothing copied) usually means a connection or
configuration problem, not a data problem — check §10 before
re-running.

### 8.2 ETL results

Per-workflow statuses: `COMPLETED` (runner returned, with its
`JOB_RUN_ID` and message), `FAILED` (runner raised — message
holds the exception), `NOT_RUN` (skipped because an earlier
workflow failed), and `(clear-snowflake)` / `CLEARED` (always
first in v5: the SNOWFLAKE-side delete before the runners). The top-level
`status` is `COMPLETED` only if every requested workflow
completed; otherwise `FAILED`. The top-level
`snowflake_job_run_id` is the *last* workflow's id — if you
need the TOA run's id specifically, read it from the TOA row
in `results`, not from the top level.

To investigate a failed workflow, in Snowflake:

```sql
SELECT * FROM TRS_ETL_WRK.VW_ETL_JOB_STORY
WHERE JOB_RUN_ID = '<id>' ORDER BY EVENT_ID;
-- Then inspect the WRK_TRS_* tables for that mapping, which the
-- simplified ETL leaves in TRS_ETL_WRK by design. They are evidence,
-- not garbage: do not drop them before you have read them, and do
-- not hand-edit them to "fix" a run -- fix the cause and re-run
-- copy, then ETL, so the mapping cleans its own work tables at
-- its start (step 5, CLEANUP_PREVIOUS_RUN in the simplified ETL).
```

### 8.3 Compare results

**Verdict.**

| Verdict | Meaning |
|---|---|
| `MATCH` | Every compared dimension's row count, key set and (where applicable) version set match, and both spines match. This is the bump passing. |
| `MISMATCH` | At least one dimension or spine does not match. The response is still a successful compare (HTTP 200) — a mismatch is an answer, not an API error. Read the differing dimensions below. |
| `PARTIAL` | At least one dimension could not be compared at all (table missing in one schema, or an error on that table). Its row counts are `-1` and its message names the cause. Fix the cause, re-run compare. |

**Per dimension.** For each dimension table you get:

- `oracle_row_count`, `snowflake_row_count`, `count_diff`
  (snowflake − oracle). A non-zero diff is the first thing to
  look at — but a zero diff is not a pass on its own (see
  coverage below).
- `matched_keys`, `oracle_only_keys`, `snowflake_only_keys`,
  plus samples (up to `sample_limit`, default 20) of the
  differing keys, pipe-joined for display. The samples are
  joined in Python for display only; the comparison itself is
  on the raw columns (see §3), so no separator can collapse
  two different keys.
  - **Oracle-only keys** = rows IDQ produced that Snowflake did
    not. Look first at the mapping for that dimension and at the
    Snowflake ETL's step story for it — a missing source row, a
    filter difference, or a lookup that did not translate.
  - **Snowflake-only keys** = rows Snowflake produced that IDQ did
    not. Look first at the insert-only guards and at whether the
    SNOWFLAKE side was truly empty at ETL start (stale SNOWFLAKE
    rows from a previous day are the classic cause — re-run copy,
    then ETL).
- **Version sets** (`C_S_*` tables only): matched / oracle-only /
  snowflake-only counts for `(PKEY_SRC_OBJECT, VERSION_SEQ)`.
  If the PKEY set matches but the version set does not, a
  timeline version is missing or extra — typically a closed row
  (end-dated) that one side emitted and the other did not. This
  is why the compare does both, not just PKEYs. Non-`C_S_*`
  tables have `null` version fields — that means "not
  applicable", not "zero".
- **Duplicate notes:** key sets collapse duplicates by
  construction, so the response also checks the arithmetic — if
  a table's row count exceeds matched + only-keys on either
  side, duplicates exist and the message says so. Exception rows
  are the known case: the same exception can legitimately
  repeat, so treat that message as "look at the rows", not as a
  failure by itself. The Exceptions dimension's compare key is
  a best-effort tuple (`SRC_SYS_ID_1, EXCEPTION_CODE,
  ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME`) because the
  table has no unique key (42 columns, no candidate key) — see
  §16 for the per-code breakdown that strengthens it.

**Spine section.** Two spines, then coverage:

- **Valid-member spine** (`STG_TRS_VALID_MEMBERS.INDV_ID`): the
  set of individuals the load considers valid. If this differs,
  every downstream dimension will differ too — fix the spine
  first.
- **Party-role spine** (`C_S_TRS_PTY_RLE.PKEY_SRC_OBJECT`):
  `INDV_ID|Member` for Member parties. Same logic: a spine
  difference explains dimension differences.
- **Coverage per dimension:** for each Member `C_S_*` dimension
  (excluding the party-role spine table itself), the distinct
  spine INDV_IDs present in it (first segment of the PKEY), IDQ
  vs Snowflake, and the diff. A dimension can have a matching
  total row count and still be wrong — right number of rows,
  wrong members. Coverage catches that. Reference (TOA
  catalogue) and Exceptions are excluded from coverage: their
  keys are not member spine keys, so including them would be
  misleading. Coverage lives on the party-role spine row, under
  its `coverage` field — not as a separate top-level section.

**Triage order for a MISMATCH (use this order, not dimension
order).** (1) Check the spines: if either spine differs, the
problem is upstream — do not debug dimensions until the spine
is explained. (2) Check coverage: a dimension with matching
counts but differing coverage has the wrong members, which
points at a filter or spine-join problem, not a row-count
problem. (3) Check counts, then key samples: oracle-only
samples point at the Snowflake mapping for that dimension;
snowflake-only samples point at SNOWFLAKE-side emptiness or an
over-inclusive Snowflake filter. (4) Check version sets: a
PKEY match with a version mismatch points at timeline/close
logic. (5) Only then open the mapping's step story in
`MDM_ETL_COMMON.COMMON.JOB_CONTROL_ETL` (filter `SOURCE='TRS'`) and its `WRK_TRS_*` tables in `TRS_ETL_WRK` for the
sample keys.

**Worked reading (illustrative numbers, not real data).**

> Phones: oracle 12,410 rows, snowflake 12,410 rows, count diff
> 0, oracle-only 0, snowflake-only 0 → Phones matches.
>
> Addresses: oracle 9,812, snowflake 9,800, diff −12,
> oracle-only 12 keys → Snowflake dropped 12 addresses IDQ kept.
> Check the Addr_2 score step for those 12 keys in
> `VW_ETL_JOB_STORY` and in `WRK_TRS_ADDR2_S50_READY` (still in
> TRS_ETL_WRK after the run, by design).
>
> Valid-member spine: oracle 48,102, snowflake 48,102, matched →
> the spine is sound, so the Address difference is in the Address
> dimension itself, not upstream.
>
> A second, subtler case: a dimension with count diff 0 and key
> sets matching, but coverage diff −3 → same number of rows,
> wrong members. Do not sign that off as a match; the coverage
> diff is the finding.

---

## 9. The control store (job history)

The control store is a SQLite database (default file
`trs_compare.db` in the API's working directory, configurable
via `CONTROL_DB_URL`). It holds **job history only — never ETL
data**. One table, `runs`, defined explicitly in
`app/repositories/run_repository.py`:

| Column | Meaning |
|---|---|
| `id` | Run UUID (the `run_id` in every response). |
| `run_type` | `copy`, `etl`, or `compare`. |
| `status` | `RUNNING`, `COMPLETED`, `FAILED`, `PARTIAL`, or `PLANNED` (dry run). |
| `started_at` / `finished_at` | UTC timestamps. A run left `RUNNING` with no `finished_at` means the API process died or was killed mid-run — it is not a completed run, and its summary is empty. (A dry-run 400 leaves no such row; a process kill still can.) |
| `summary_json` | The full summary as JSON: per-table results for copy, per-workflow results for ETL, `{verdict, dimensions, spine}` for compare. This is what `GET /runs/{id}` returns as `results`. |
| `message` | The one-line summary, including any `run_label` / `copy_run_id` you supplied. |

**Query it directly** (useful when the API is down, or for
history beyond the `GET /runs` limit):

```bash
sqlite3 trs_compare.db
sqlite> SELECT id, run_type, status, started_at FROM runs ORDER BY started_at DESC LIMIT 20;
sqlite> SELECT message FROM runs WHERE id = '<run_id>';
sqlite> SELECT summary_json FROM runs WHERE id = '<run_id>' AND run_type = 'compare';
```

**Retention.** There is no built-in retention or pruning: the
store grows by one row per run, forever, until you prune it.
For a daily job (3 runs/day), that is about 1,000 rows/year —
trivial for SQLite, but if you ever run the API in a loop or
with a scheduler at high frequency, prune deliberately:

```sql
DELETE FROM runs WHERE started_at < date('now', '-90 days');
```

Back the file up like any other job-history database: copy the
file while the API is stopped, or use SQLite's backup API. Do
not delete the file to "reset" the API — you will lose the
audit trail for every previous run, and the API will simply
recreate an empty one on next start.

**If the history "disappears".** You are almost certainly
running the API from a different working directory than before,
so `sqlite:///./trs_compare.db` resolves to a different file.
Set `CONTROL_DB_URL` to an absolute path (for example,
`sqlite:////var/lib/trs_compare/trs_compare.db`) in production
so the location does not depend on where you happened to start
the server.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Copy returns `SKIPPED_MISSING` for 4 tables, status `PARTIAL` | §4.4 not done yet | Supply the four definitions, regenerate `tables.py`, re-run copy |
| Copy `FAILED` on a table: "relation does not exist" / "table does not exist" (Snowflake) | Step A DDL not applied, or applied to the wrong database/schema | Apply `sql/01_etl_wrk.sql` and `sql/04_missing_tables.sql` to `MDM_ETL_TRS.TRS_ETL_WRK`; verify with the §4.3 query |
| Copy `FAILED` on a table: "relation does not exist" (Oracle) | Oracle user lacks `SELECT` on that schema, or the table name/schema in the catalog is wrong for your site | Check grants with `sqlplus` as the same user; check the catalog's `oracle_schema` for that table |
| Copy count mismatch after INSERT | Column mismatch (Oracle has a column Snowflake does not, or vice versa — see the silent-drop warning in §4.4), or a type the driver converted (e.g. a large `NUMBER`, a timestamp with timezone) | Compare the Oracle table definition with the Snowflake table; re-generate DDL and `tables.py` from a fresh export; check the type mapping in §4.3 |
| Copy `FAILED` on every table at once | Connection or configuration problem (wrong host/service/account, bad credentials, no default warehouse) | Run `GET /health?check_db=true` first; fix configuration before re-running — do not re-run copy repeatedly hoping it clears |
| ETL `FAILED`, Snowflake error about a missing table | A lookup table missing (often one of the four in §4.4), or the ETL procedures not installed in `TRS_ETL_WRK` | Check `TRS_ETL_WRK` for the procedures and lookup tables (§4.2 verification); check `MDM_ETL_COMMON.COMMON.JOB_CONTROL_ETL` (filter `SOURCE='TRS'`) for the last completed step |
| ETL `FAILED`, Snowflake error about a missing procedure | Runners not installed, or installed in a different schema | Re-run §4.2; confirm the procedure names match `WORKFLOW_PROCEDURES` in `etl_service.py` exactly |
| ETL succeeded but compare shows snowflake-only rows everywhere | SNOWFLAKE side was not empty at ETL start (a previous day's run left rows, and the copy step was skipped) | Re-run copy (it truncates target tables), then ETL, then compare |
| Compare `PARTIAL`, a dimension's counts are `-1` | Table missing in `TRS_ETL_WRK` (copy did not run, or DDL missing) | Run copy first; check the table exists in both schemas |
| Compare `MISMATCH` on one dimension only, spine matches | The difference is in that dimension's mapping, not upstream | Follow the triage order in §8.3: coverage, counts, samples, version sets, then the mapping's step story |
| Compare `MISMATCH` on every dimension, spine also differs | Upstream problem: valid-member spine or party-role spine | Fix the spine first (§8.3); do not debug dimensions until it is explained |
| Snowflake login opens a browser on the server / hangs | `SNOWFLAKE_AUTHENTICATOR=externalbrowser` on an unattended server | Switch to `oauth` with a token from your IdP (§4.7) |
| Snowflake auth error on the first call of the day, after working yesterday | Expired OAuth token (engines are lazy, so expiry only shows on first use) | Refresh the token via your IdP, restart the API, verify with `GET /health?check_db=true` |
| All Snowflake calls fail with a warehouse error | No default warehouse for the user/role, and `SNOWFLAKE_WAREHOUSE` empty | Set `SNOWFLAKE_WAREHOUSE` to a warehouse the role can use, or set a default warehouse for the user/role |
| API returns 401 | `API_KEY` is set and the `X-API-Key` header is missing or wrong | Send the header; for local development, leave `API_KEY` empty |
| API returns 400 on copy | Unknown table name in `tables` | Check the name against `GET /config/tables`; names are case-insensitive, but must match a catalog table exactly |
| API returns 400 on compare | Filter matches no dimensions | Check dimension names against `GET /config/tables` / Appendix A; a misspelled filter is rejected rather than reporting a false `MATCH` |
| API returns 422 | Request body fails validation (e.g. `sample_limit` outside 0–200, wrong field type) | Read the `detail` list in the response (FastAPI standard shape); fix the field it names |
| API returns 404 on `GET /runs/{id}` | Unknown run id (typo, or a different control-store file — see §9) | Check the id from the POST response; check `CONTROL_DB_URL` points at the same file |
| POST blocks / client times out on a long copy | Synchronous endpoints (§5) + a short client timeout | Use a client with no timeout (`curl --max-time 0`) or a longer timeout; watch progress from a second terminal with `GET /runs`; do not assume a timed-out client means the server stopped (check the run's status first) |
| Two copies run at once, results look mixed | No lock in the code (§5, §14) | Stop both, re-run a single copy, then ETL, then compare; agree on one operator |
| Run history "disappears" after a restart | API started from a different working directory, so `trs_compare.db` resolved elsewhere | Set `CONTROL_DB_URL` to an absolute path (§9) |
| Oracle connection fails | Wrong host/service, or the user lacks `SELECT` on one of the three schemas | Check `.env`, test with `sqlplus` / SQL Developer as the same user, and confirm grants on `STAGING`, `HHS_MDM`, and `RDM` |
| Tests fail with "module not found" | Dependencies not installed in the active venv | Activate the venv and `pip install -r requirements.txt`; do not install into the system Python (PEP 668 will block it — use a venv) |

---

## 11. Deployment and operations

**Running the server.** Development:

```bash
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Production (single host, behind a reverse proxy — see below):

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1
```

**Workers: use 1.** Uvicorn's `--workers` runs separate
processes. With SQLite as the control store, multiple workers
share one file — SQLite handles concurrent writes with locking,
but the copy job's "one run at a time" rule (§5) is *not*
enforced by the code, and multiple workers make concurrent runs
easier to start by accident. One worker, one operator, one run
at a time is the supported deployment. If you need more
throughput, that is a design change (a job queue with a lock),
not a flag change.

**TLS / HTTPS.** This project does not terminate TLS itself.
For any deployment beyond localhost, put it behind a reverse
proxy (nginx, or your site's standard) that terminates HTTPS
and forwards to `127.0.0.1:8000`, and set `API_KEY`. An API
key sent over plain HTTP on a shared network is not a secret.
The guide does not prescribe your proxy configuration — use
your site's standard — but "no HTTPS + API key" is not an
acceptable production combination, and the pre-production
checklist (§17) calls it out explicitly.

**Logging.** There is no logging configuration in this project:
no log files, no log levels, no structured logs. Uvicorn's
default access/error logs are all you get, and the API itself
never logs credentials, tokens, or row data (it returns counts
and key samples in responses, which is different from logging
them — but do not add request logging that dumps bodies
without thinking about what those bodies contain: sample keys
are business keys). If you need audit logging beyond the run
store, add it as a deliberate feature with a retention policy,
not by turning on debug logging and hoping.

**Scheduling (if you ever automate the morning run).** The
clean automation is a scheduler (cron, or your site's job
scheduler) that, after the IDQ job reports success: (1) calls
`GET /health?check_db=true`, (2) calls `POST /runs/copy`,
checks the body status is `COMPLETED`, (3) calls
`POST /runs/etl`, checks `COMPLETED`, (4) calls
`POST /runs/compare`, records the verdict. Each step must check
the *body* status, not just HTTP 200 (§6). Do not schedule the
copy on a fixed clock that might fire while IDQ is still
running — trigger it from IDQ completion, or accept that a
clock-triggered copy can bake a half-finished expected side
into the compare. The API itself has no scheduler, no cron, and
no retry logic: retries are the operator's (or the scheduler's)
decision, and the re-run rule is always "copy, then ETL, then
compare" from the top.

**Backups.** Back up two things: the `.env` (securely, with
your site's secret management — not in the same place as the
code, and never in version control) and the control-store file
(`trs_compare.db`, see §9). The Snowflake schemas do not need
a separate backup for this job: they are rebuilt every morning
by the copy, and the ETL can be re-run from a fresh copy.

---

## 12. Testing

**Run the suite.** From the project root (the directory holding
`pyproject.toml`), with your virtual environment activated:

```bash
pytest tests/ -q
# 48 tests, all without Oracle or Snowflake.
# `python -m pytest tests/ -q` works identically.
```

On Windows, the same commands apply after activating the venv
(`.\.venv\Scripts\activate`); the test run itself is identical.
Both invocation styles work: `pyproject.toml` sets
`pythonpath = ["."]` and `tests/__init__.py` exists, so the
project root is on `sys.path` for `import app` either way.
If you ever see `ModuleNotFoundError: No module named 'app'`
from a test run, you are almost certainly running pytest from
a different directory, or with an old checkout that predates
those two settings — run it from the project root, or install
the project once with `pip install -e .`, which makes `app`
importable from anywhere.

**SQLite harness — testing the compare without fakes, and
without Snowflake.** The fake-repository tests prove the
verdict logic, but a fake's key difference is Python set
arithmetic, not SQL `EXCEPT`, and its coverage count is
Python string-splitting, not `SPLIT_PART`. The SQLite
harness (`tests/sqlite_harness.py`,
`tests/test_sqlite_harness.py`, scenario SQL in
`test_harness_data/`) runs the real compare service and the
real `SnowflakeRepository` against a real SQLite database:
an in-memory database is attached under the name
`TRS_ETL_WRK`, so the schema-qualified tables the compare
asks for are real tables, and every catalog table is created
from `app/domain/tables.py`. Scenario SQL inserts both
`DATA_SOURCE` sides by hand — IDQ rows and the rows a
correct (or faulty) ETL would produce — because the
Snowflake ETL does not exist yet. That is the point: the
harness tests the compare, the part that is built, against
the success and failure shapes the ETL will have to produce,
and when the ETL lands these scenarios become its acceptance
cases. The only production-code change the harness needed
was in `coverage_count()`: on SQLite it uses
`SUBSTR`/`INSTR` instead of `SPLIT_PART` (same semantics);
the Snowflake path is unchanged, and every other compare
statement was already plain Core SQL.

Scenarios (see `test_harness_data/README.md` for the full
table): matching Phones and Demographics, a row missing on
the Snowflake side, an extra row on the Snowflake side, a
PKEY match with a missing timeline version, duplicate keys,
a spine gap with a matching dimension, a coverage gap,
matching Exceptions, and the pre-ETL state (Snowflake side
empty — an expected `MISMATCH`, not an ETL failure; that
scenario is retired, not edited, once the ETL fills the
side). To add a case, add a commented SQL file in
`test_harness_data/` and a test that loads it and asserts
counts, keys, samples and verdict — not just the verdict.

**File-based harness and `GET /sqlite/tables` (v5.4.0).**
By default the harness is in-memory: fast, isolated, and
gone when the test ends. For inspecting data by hand — or
for showing a colleague what a scenario contains — build a
persistent file instead:

```bash
python scripts/build_sqlite_harness_db.py --db ./trs_harness.db \
    --fresh 00_common_spine.sql 01_match_phones.sql
SQLITE_HARNESS_DB_PATH=./trs_harness.db uvicorn app.main:app --host 127.0.0.1 --port 8000
curl http://127.0.0.1:8000/sqlite/tables
```

The file IS the `TRS_ETL_WRK` database: the harness
ATTACHes it under that name, so the compare sees
`TRS_ETL_WRK.<table>`, while the file opened directly (in
`sqlite3`, a DB browser, or this endpoint) shows `<table>`.
Reopening a file does not drop it — tables are created
only if missing — so without `--fresh`, loading a scenario
twice appends its rows twice; use `--fresh` when you mean
to rebuild.

`GET /sqlite/tables` is read-only inspection, not a
compare: it lists every table actually in the file
(alphabetically, including tables outside the catalog),
with its total row count, and for tables carrying the
discriminator column, the count grouped by `DATA_SOURCE`:

```json
[
  {"table": "C_S_TRS_PTY_RLE_PHN", "row_count": 4,
   "has_discriminator": true,
   "counts_by_discriminator": {"IDQ": 2, "SNOWFLAKE": 2}},
  {"table": "STG_TRS_CD_REF", "row_count": 1,
   "has_discriminator": false, "counts_by_discriminator": null}
]
```

Inputs report only a total (`counts_by_discriminator` is
null, not an empty dict — an empty dict would be
ambiguous with "the table is empty"). The endpoint
requires the API key like every endpoint except
`/health`, takes no path from the request (it reads only
`SQLITE_HARNESS_DB_PATH`, so a caller cannot point it at
an arbitrary file), opens the file query-only, and
answers 404 — never an empty list — when the setting is
unset or the file does not exist, so a missing database
cannot masquerade as an empty one. It does not touch
Snowflake, Oracle, or the run store.

**Generator fix found by the harness.** Creating every
catalog table exposed a bug in both DDL generators: their
column-list regex ran past tables whose DDL ends with a
clause like `) CACHE ;` and swallowed the next table's
columns. `LOOKUP_CODE_VALUE` shipped with 21 columns (its
own 11, plus the next table's 10 with different lengths) —
duplicate column names that would make both the Table
object and the Snowflake DDL invalid. Both generators now
scan for the balanced closing paren instead, fail loudly on
any duplicate column, and the regenerated
`app/domain/tables.py` and `sql/01_etl_wrk.sql` contain
only the correct 11 columns for that table. If you applied
the old DDL to Snowflake, that table's creation would have
failed outright — re-apply the new file for that table.

**What each file covers.**

| File | What it proves | Database needed |
|---|---|---|
| `tests/test_catalog.py` | Catalog integrity (no duplicates, every expected table has a compare key, inputs have none, the four missing tables are exactly those four, unknown names rejected, dimension filtering, Provider scope), explicit table definitions (same table in two schemas gives independent Tables with the same columns, unknown names rejected), and fluent query building (a Core `EXCEPT` statement compiles to SQL containing `EXCEPT` and both schemas, without a database). | None. |
| `tests/test_api.py` | Health (plain and with-db-checks shape), dry-run copy plan (including the four missing tables flagged), dry-run unknown table → 400 with no orphan run, dry-run → `GET /runs/{id}` round-trip, `GET /runs` listing, run-repository round-trip, and compare-run readability via `GET /runs/{id}`. API tests inject a temp-database run repository via `dependency_overrides` — they never touch the real `trs_compare.db`. | Temp SQLite only (run history). No Oracle/Snowflake. |
| `tests/test_services.py` | Service logic with fake repositories (see below): copy destinations and the discriminator model, missing-table partial, compare MATCH / MISMATCH / PARTIAL, empty-filter rejection, ETL order, job-run-id parsing, unknown-workflow rejection, empty-workflow rejection, and the ETL clear step (SNOWFLAKE side deleted, IDQ side preserved). | None at all. |

**Fake repositories, in one paragraph.** Services take
repositories as arguments, so a test can pass a fake — a plain
Python class with the same method names, storing rows in dicts
keyed by (schema, table) — instead of a real repository. The
service cannot tell the difference, because it only calls
methods, never SQL or connections. That is how the discriminator model
(IDQ side vs SNOWFLAKE side) and the compare verdicts are
tested with no database.
**What fake tests do not prove:** the repository SQL itself.
If the real `key_difference` SQL had a bug the fake's
dict-based version did not, the fake test would still pass.
Fake tests prove service logic; repository SQL still needs one
real run against Oracle and Snowflake (§17). See the earlier
explanation in this conversation for the full version of this
distinction, with examples.

**Writing a new service test.** Copy the pattern in
`tests/test_services.py`: build a `FakeOracle` /
`FakeSnowflake` with the rows your case needs (spine rows on
both sides, so spine verdicts do not interfere unless that is
what you are testing), call the service function directly with
the fakes, and assert on the returned models and verdict —
not on SQL strings. If your test needs a new repository method,
add it to the fake first, then to the real repository, then to
the service — in that order, so the test fails before the fix
and passes after it.

**Testing against real databases, safely.** Never test against
production Oracle or production Snowflake first. The safe order
is: (1) unit tests (above), (2) dry-run copy against the real
API (no databases touched), (3) subset copy (one small input
table, one small expected table) against a non-production
Snowflake database with a non-production Oracle user, (4) full
copy → ETL → compare against non-production, (5) only then the
production bump, with the §17 checklist signed off. If a step
fails, fix it at that step — do not jump to production hoping
the failure was specific to the test environment.

**A note on the test environment in this delivery.** The tests
were run in a venv with `fastapi`, `sqlalchemy`,
`pydantic-settings`, `httpx`, and `pytest` installed. The full
`requirements.txt` (which additionally includes `oracledb` and
`snowflake-sqlalchemy`) is what you install for production use;
the tests do not need the database drivers, because they never
construct a real Oracle or Snowflake engine. If you run the
tests in a fresh venv with `requirements.txt` installed, they
will pass the same way.

---

## 13. Maintainer guide — adding a table, a workflow, a dimension, a compare

**Adding a table (the most common change).** Suppose Oracle
gains a new source table the ETL should read, or a new target
the ETL writes:

1. Add a `TableSpec` to `app/domain/catalog.py` — to
   `INPUT_TABLES` (with its Oracle schema, `copy_role="input"`,
   domain, and dimension) or to `EXPECTED_TABLES` (with its
   Oracle schema, domain, dimension, and `compare_key`). In v5
   every table goes to `TRS_ETL_WRK`; expected tables additionally
   get the `DATA_SOURCE` column (the DDL generator adds it, and
   `generate_tables.py` adds it to `tables.py` — do not add it
   by hand to an input table).
2. Regenerate the DDL: `python
   scripts/generate_snowflake_ddl.py` (see its `--help` for
   the Oracle export directory argument), review the diff in
   `sql/01_etl_wrk.sql`, and apply the new table's DDL to
   `TRS_ETL_WRK`.
3. Regenerate the table definitions: `python
   scripts/generate_tables.py --oracle-dir <exports> --out
   app/domain/tables.py`, review the diff, and commit it.
   Steps 2 and 3 are a pair — doing only one leaves the DDL and
   the code disagreeing, which is exactly the silent-drop
   failure mode in §4.4.
4. Run the dry-run copy (`POST /runs/copy` with
   `dry_run: true`) and confirm the new table appears in the
   plan. Then run the tests (`pytest tests/ -q`), then a subset
   copy of just the new table against non-production (§12).

**Changing a column.** Same pair as above: regenerate DDL and
`tables.py` from a fresh export, review both diffs, apply the
DDL, commit both. Do not hand-edit `tables.py` for a column
change if you can regenerate — hand edits drift from the
generator's output and the next regeneration will overwrite
them silently. Hand edits belong only in `sql/04_` (the missing
tables), which the generator never touches.

**Adding a workflow.** Add its runner procedure name to
`WORKFLOW_PROCEDURES` in `app/services/etl_service.py` (the
allowlist — a procedure name reaches the repository only from
here), install the runner in `TRS_ETL_WRK`, and add the workflow
name to the ETL endpoint's allowed list in the guide (§6) and
to a test in `tests/test_services.py` (order, parsing, failure
handling). The default workflow order (`["toa", "ongoing"]`)
lives in the `EtlRequest` model — change it there, not in the
service, if the default order should change.

**Adding a dimension.** A dimension is a catalog row, not a
code change: add the expected table to `EXPECTED_TABLES` with
its domain, dimension name, and compare key, and follow the
"adding a table" steps above for DDL and table definitions.
The compare picks it up automatically from the catalog. If the
dimension needs a different compare key than PKEY (like
Exceptions), set that key explicitly in the catalog — do not
special-case it in the compare service.

**Adding a new kind of compare (hash, per-code breakdown,
day-over-day).** The pattern, for each, is the same three
steps, in this order: (1) add a repository method that returns
a typed result (e.g. `hash_difference(left, right, columns) ->
KeyDifference`, or `exception_code_counts(table) ->
list[CodeCount]`), implemented with Core statements over
explicit tables; (2) add the service logic that calls it and
merges its result into `DimensionCompare` (or a new response
model — do not overload `DimensionCompare` with unrelated
fields if the new compare has a genuinely different shape);
(3) add a fake-repository test for the service logic and a
real-database check for the repository SQL (§12). For the
row-hash compare specifically (§16): start with Demographics
only, hash a small, explicit column list per PKEY (not `*` —
a `*` hash will drown you in formatting differences on
nullable columns), and report only differing PKEYs, not full
row dumps.

---

## 14. Limitations, assumptions, and what this project does not do

This section is the honest list. If you hit one of these and it
surprises you, the guide has failed — tell the maintainer, and
this section should grow.

- **No value comparison.** Counts + key sets + version sets
  only. Two rows with the same PKEY but different values will
  compare as matching. See §16 for the hash compare that closes
  this gap, starting with Demographics.
- **No Provider domain, no deactivation execution.** See §1.
- **No automatic IDQ completion detection, no scheduling, no
  retries, no job queue.** The operator (or a scheduler you
  build around the same endpoints) drives the job. See §5, §11.
- **No concurrency control.** One copy / ETL / compare at a
  time, enforced by agreement, not by code. See §5.
- **Synchronous endpoints.** Long jobs block the HTTP request.
  See §5.
- **No background workers, no progress streaming.** A running
  copy's progress is visible only as its final per-table
  results, plus the `RUNNING` row in `GET /runs`. There is no
  "table 12 of 49" progress endpoint. If you need one, it is a
  feature (a progress callback in the copy service, recorded
  in the run store), not a configuration change.
- **No TLS, no logging, no metrics.** See §11. The API does not
  terminate HTTPS and does not emit structured logs or metrics.
- **No retention for the run store, no pruning.** See §9.
- **Snowflake data is latest-day only.** `TRS_ETL_WRK` and `TRS_ETL_WRK`
  are truncated on every copy. History lives in the run store's
  summaries, not in Snowflake. If you need daily Snowflake
  history, that is a new schema design (dated snapshots), not a
  flag.
- **No handling of Oracle schema changes at runtime.** A new
  column, a renamed table, or a changed type requires
  regeneration (§13). The copy will not auto-adapt, by design.
- **Assumptions baked in, worth re-checking at your site:**
  one Oracle user can `SELECT` from all three schemas; one
  Snowflake database is MDM_ETL_TRS with the single TRS_ETL_WRK schema; the
  ETL procedures live in `TRS_ETL_WRK` and use unqualified names;
  `PKEY_SRC_OBJECT`'s first pipe segment is the spine id for
  Member parties; the simplified ETL's insert-only guards are
  the reason the SNOWFLAKE side must start empty. If any of these is false
  at your site, the design needs revisiting, not just a config
  tweak — say so early, before the first production bump.

---

## 15. Frequently asked questions

**Q: Why one schema with a discriminator, instead of separate
IDQ and WORK schemas?**
A: Because the expected side (IDQ targets) and the actual side
(Snowflake targets) are the same tables, told apart by
`DATA_SOURCE` (`'IDQ'` vs `'SNOWFLAKE'`) in `TRS_ETL_WRK`. One
schema means one set of tables, one set of procedures, and one
place to look — and the compare is a filter on `DATA_SOURCE`,
not a cross-schema join. See §2.

**Q: Why not just compare Oracle directly against Snowflake,
without copying IDQ targets to Snowflake first?**
A: Because the compare would then be a cross-database join for
every dimension, with two drivers, two type systems, and no
single place to run `EXCEPT`. Copying the IDQ side into the
same Snowflake table (with `DATA_SOURCE='IDQ'`) makes the
compare a set of Snowflake-to-Snowflake queries, filtered by
`DATA_SOURCE`, which are faster, simpler, and type-consistent.
The copy is the price of that simplicity, and it is also the
audit trail: the IDQ rows in `TRS_ETL_WRK` are the frozen expected
result for that day.

**Q: The copy is PARTIAL because of the four missing tables.
Can I run ETL anyway and just ignore those dimensions?**
A: No — not for a production bump. The missing tables are
*lookup* tables, not dimensions. The ETL's helper functions
read them for code translation, junk-name checks, match-code
text, and area-code checks. A missing lookup does not just
drop a dimension; it can fail a mapping or silently change its
output. Fix §4.4 first.

**Q: Compare says MISMATCH, but I re-ran it and got MATCH.
What happened?**
A: Almost certainly the second run followed a fresh copy (which
reset) while the first run followed a stale SNOWFLAKE side, or vice
versa. A compare result is only meaningful for the
copy → ETL → compare sequence it belongs to — that is what
`copy_run_id` on the ETL and compare requests is for (§6).
Quote the run ids when you report a verdict, not just the
verdict.

**Q: Can I run the API with `uvicorn --reload` in production
so code changes pick up automatically?**
A: No. `--reload` restarts the server on file changes, which
will kill a running copy mid-job and leave a `RUNNING` row
with no finish (§9). Deploy code changes by stopping the API,
deploying, and restarting it deliberately, between morning
runs, not during one.

**Q: Why does `GET /runs` only return 50 runs?**
A: Because there is no pagination beyond `limit` (§6). Raise
`limit` for a longer list, or query the control store directly
(§9) for full history.

**Q: The guide says "expected vs actual" but the code says
TRS_ETL_WRK / TRS_ETL_WRK. Which should I use in a ticket?**
A: Use Expected (IDQ) vs Actual (Snowflake) in the ticket
title and summary, and quote the schema names and run ids in
the detail. The business reader needs the first; the engineer
debugging it needs the second.

---

## 16. Suggested follow-ups, in priority order

These are suggestions, not promises — each is a small, scoped
change following the §13 pattern, and none of them changes the
daily operator flow until you decide it should.

1. **Row-hash compare for Demographics** (see §1 and §13).
   Counts + keys prove the same rows exist, not that they hold
   the same values. Start with Demographics (small,
   high-value), hash an explicit column list per PKEY, report
   only differing PKEYs. Then Names and Alternate IDs. Do not
   start with Addresses (63 columns, mostly NULLs).
2. **Exception-code breakdown.** Counts per `EXCEPTION_CODE`
   in `EXC_STG_BAD_REC_MEMB`, IDQ vs Snowflake, as a second
   opinion on the Exceptions dimension, whose compare key is
   best-effort (§8.3). The SQL is a one-line `GROUP BY` on both
   schemas; it was left out only to keep this release to the
   counts + PKEY contract you asked for.
3. **Day-over-day delta.** Store each compare's differing-key
   sets and report only *new* differences versus yesterday, so
   a known, accepted difference stops paging the operator every
   morning. The run store already holds each compare's full
   summary (§9) — the delta is a reader over those summaries,
   not a new database.
4. **A progress endpoint for long copies.** Record per-table
   completion in the run store as the copy proceeds, so a
   second terminal can watch "table 12 of 49" instead of only
   seeing `RUNNING` (§14). This needs a run-store update per
   table, which is a small service change — but do it only if
   long copies are actually a daily pain, not in anticipation.
5. **A lock / job queue.** If two operators (or a scheduler
   and an operator) might run the job at once, enforce
   one-run-at-a-time in code (§14) instead of by agreement.
   This is deliberately last: it is the only suggestion here
   that changes the deployment model, and it should wait until
   the manual flow is proven.

---

## 17. Pre-production checklist

- [ ] Step A DDL applied to the right Snowflake database/schema,
      and the §4.3 verification query returns 48 tables in
      TRS_ETL_WRK (29 inputs + 19 targets, after sql/01 + sql/04).
- [ ] The four missing definitions supplied (§4.4, all three
      steps including `tables.py` regeneration), and copy no
      longer reports `SKIPPED_MISSING`.
- [ ] Snowflake ETL (simplified package) installed in `TRS_ETL_WRK`
      (§4.2 verification passed) and run once by hand,
      successfully, before the API calls it — including its own
      §11 compile check and row-count parity run on a
      non-production database.
- [ ] SSO mode confirmed for the API server (`oauth` with a token
      from your IdP, not `externalbrowser` on a server), and
      `GET /health?check_db=true` passes after a token rotation.
- [ ] Oracle user is read-only with `SELECT` on `STAGING`,
      `HHS_MDM`, `RDM`; Snowflake role verified for `SELECT`,
      `INSERT`, `TRUNCATE`, and procedure execution on the
      comparison schemas (especially `TRUNCATE` — §4.7).
- [ ] `API_KEY` set for any shared deployment, HTTPS in front of
      the API (§11), `.env` not in version control, and
      `CONTROL_DB_URL` set to an absolute path (§9).
- [ ] Uvicorn run with `--workers 1` and without `--reload` in
      production (§11).
- [ ] First full morning run done end-to-end (copy → ETL →
      compare) on a non-production Snowflake database, with the
      compare verdict read and understood before it is trusted
      for the production bump — including one deliberate
      `MISMATCH` triage using §8.3, so the operator has practised
      the triage order before a real mismatch.
- [ ] A decision recorded on the §16 suggestions (hash compare,
      exception breakdown, day-over-day delta) — even if the
      decision is "later", write it down so it is not
      rediscovered every morning.
- [ ] One operator (or one scheduler) agreed as the runner for
      the daily job, until a lock exists (§14).

## Appendix A. Complete table catalog (generated from the code)

The tables below are generated from `app/domain/catalog.py`
itself, not hand-typed, so they cannot drift from the code
without the generator being re-run. If a table is missing
here, it is missing from the catalog — and therefore from the
copy and the compare. Destination is `TRS_ETL_WRK` for every table (see §2, §7);
for expected tables, see §7 for the discriminator and the
SNOWFLAKE-side clear rule.

### Input tables (30)

| Table | Oracle schema | Domain | Dimension | Destinations in Snowflake |
|---|---|---|---|---|
| `C_B_PTY_RLE_ALT_ID` | HHS_MDM | Member | Reference — MDM Alt-ID Base | TRS_ETL_WRK |
| `C_B_PTY_RLE_ALT_ID_XREF` | HHS_MDM | Member | Reference — MDM Alt-ID Xref | TRS_ETL_WRK |
| `C_B_PTY_RLE_REL_XREF` | HHS_MDM | Member | Reference — MDM Relationship Xref | TRS_ETL_WRK |
| `EXC_LOOKUP_CODE_VALUE` | STAGING | Member | Reference — Exception Codes | TRS_ETL_WRK |
| `LOOKUP_CODE_VALUE` | STAGING | Member | Reference — Code Values | TRS_ETL_WRK |
| `REF_DYLGHT_SVNGS_TM` | STAGING | Member | Reference — Daylight Saving | TRS_ETL_WRK |
| `REF_JUNK_NAME_LIST` | — unknown — | Member | Reference — Junk Names | — (skipped until definition supplied) |
| `REF_MATCHCODE_DESC` | — unknown — | Member | Reference — Match Codes | — (skipped until definition supplied) |
| `REF_PHN_AREA_CD` | RDM | Member | Reference — Phone Area Codes | — (skipped until definition supplied) |
| `STG_TRS_CD_REF` | STAGING | Member | Reference — Code | TRS_ETL_WRK |
| `STG_TRS_CV_ED_MCI_EDG_INDV` | STAGING | Member | Reference — Crosswalk | TRS_ETL_WRK |
| `STG_TRS_DC_CASES` | STAGING | Member | Source — DC Cases | TRS_ETL_WRK |
| `STG_TRS_DC_CASE_INDV` | STAGING | Member | Source — DC Case Individuals | TRS_ETL_WRK |
| `STG_TRS_DC_PRIMARY_PAYEE` | STAGING | Member | Source — DC Payees | TRS_ETL_WRK |
| `STG_TRS_D_CV_DC_MCI_ALIAS` | STAGING | Member | Source — DC/MCI Aliases | TRS_ETL_WRK |
| `STG_TRS_D_CV_DC_MCI_INDV` | STAGING | Member | Source — DC/MCI Individuals | TRS_ETL_WRK |
| `STG_TRS_D_CV_DC_MRG_SPRT_INDV` | STAGING | Member | Source — Merged/Split Individuals | TRS_ETL_WRK |
| `STG_TRS_D_CV_ED_MCI_EDG_INDV` | STAGING | Member | Source — EDG Individuals | TRS_ETL_WRK |
| `STG_TRS_D_CV_MCI_EDG_INDV_TOA` | STAGING | Member | Source — EDG TOA | TRS_ETL_WRK |
| `STG_TRS_D_DC_ALIAS` | STAGING | Member | Source — DC Aliases | TRS_ETL_WRK |
| `STG_TRS_D_DC_CASES` | STAGING | Member | Source — DC Cases (detail) | TRS_ETL_WRK |
| `STG_TRS_D_DC_INDV` | STAGING | Member | Source — DC Individuals | TRS_ETL_WRK |
| `STG_TRS_D_DC_PRIMARY_PAYEE` | STAGING | Member | Source — DC Primary Payees | TRS_ETL_WRK |
| `STG_TRS_D_DC_RELATIONSHIPS` | STAGING | Member | Source — DC Relationships | TRS_ETL_WRK |
| `STG_TRS_D_DC_RELATIONSHIPS_A` | STAGING | Member | Source — DC Relationships (archive) | TRS_ETL_WRK |
| `STG_TRS_D_INDV_ADDR` | STAGING | Member | Source — Individual Addresses | TRS_ETL_WRK |
| `STG_TRS_D_IN_MANAGED_CARE` | STAGING | Member | Source — Managed Care | TRS_ETL_WRK |
| `STG_TRS_D_LU_TOA` | STAGING | Member | Source — TOA Lookup | TRS_ETL_WRK |
| `STG_TRS_H_DC_INDV` | STAGING | Member | Source — DC Individual History | TRS_ETL_WRK |
| `V_LOOKUP_CODE_VALUE` | — unknown — | Member | Reference — Code Values (view) | — (skipped until definition supplied) |

### Expected tables (19)

| Table | Oracle schema | Domain | Dimension | Compare key |
|---|---|---|---|---|
| `C_S_LU_TOA` | HHS_MDM | Reference | TOA Catalogue | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY` | HHS_MDM | Member | Demographics | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_MNG_ATTR` | HHS_MDM | Member | Managed Attributes | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_NM` | HHS_MDM | Member | Names | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE` | HHS_MDM | Member | Party Role | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_ADDR` | HHS_MDM | Member | Addresses | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_ALT_ID` | HHS_MDM | Member | Alternate IDs | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_EADDR` | HHS_MDM | Member | Emails | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_PHN` | HHS_MDM | Member | Phones | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_PLN` | HHS_MDM | Member | Plans | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_REL` | HHS_MDM | Member | Relationships — Member to Member | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_REL_PROV` | HHS_MDM | Member | Relationships — Member to PCP | `PKEY_SRC_OBJECT` |
| `C_S_TRS_PTY_RLE_TOA` | HHS_MDM | Member | TOA | `PKEY_SRC_OBJECT` |
| `DQM_ADDRESS` | STAGING | Member | Addresses — Audit | `PTY_SRC_KEY, ADDR_SRC_KEY` |
| `EXC_STG_BAD_REC_MEMB` | STAGING | Member | Exceptions | `SRC_SYS_ID_1, EXCEPTION_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME` |
| `STG_TRS_DEACTIVATED_RELATIONSHIPS` | STAGING | Member | Deactivation — Relationship Capture | `PKEY_SRC_OBJECT` |
| `STG_TRS_DEACTIVED_MEMBERS` | STAGING | Member | Deactivation — Party Capture | `INDV_ID` |
| `STG_TRS_D_UNQ_ADDR` | STAGING | Member | Addresses — Unique | `ADDR_ID` |
| `STG_TRS_VALID_MEMBERS` | STAGING | Member | Spine — Valid Members | `INDV_ID, SRC_TBL` |

Counts: input specs 30 (26 with DDL in sql/01_etl_wrk.sql + 4 missing), expected specs 19.
After sql/01 + sql/04 are applied: TRS_ETL_WRK holds 48 tables (29 inputs + 19 targets).

---

## Appendix B. Complete configuration reference

Every setting, its default, and whether it is required. All are
read from environment variables (`.env` file supported via
pydantic-settings; see `app/core/config.py`). "Required" means
the API will raise a clear error on first use of that database
if it is missing — not at startup, because engines are lazy
(see §4.7). An empty string for a password/token means "not
set"; an empty string for a schema/warehouse/role name means
"use the site default for that user/role".

| Variable | Default | Required? | Meaning |
|---|---|---|---|
| `API_KEY` | (empty) | No — but yes for any shared deployment | If set, clients must send `X-API-Key`. If empty, no header required (local development only). |
| `CONTROL_DB_URL` | `sqlite:///./trs_compare.db` | No | SQLAlchemy URL for the run store (§9). Use an absolute path in production. |
| `ORACLE_HOST` | `localhost` | Yes, for production (default is a local placeholder) | Oracle host. |
| `ORACLE_PORT` | `1521` | No | Oracle port. |
| `ORACLE_SERVICE` | `ORCL` | Yes, for production (default is a local placeholder) | Oracle service name. DSN form: `host:port/service`. |
| `ORACLE_USER` | (empty) | Yes | Oracle user. Must have `SELECT` on `STAGING`, `HHS_MDM`, `RDM`. |
| `ORACLE_PASSWORD` | (empty) | Yes | Oracle password. Never logged. |
| `SNOWFLAKE_ACCOUNT` | (empty) | Yes | Snowflake account identifier. |
| `SNOWFLAKE_USER` | (empty) | Yes | Snowflake user. |
| `SNOWFLAKE_PASSWORD` | (empty) | Only for `authenticator=snowflake` | Snowflake password (service-user mode). Never logged. |
| `SNOWFLAKE_AUTHENTICATOR` | `snowflake` | No | `snowflake` \| `oauth` \| `externalbrowser`. See §4.7. |
| `SNOWFLAKE_OAUTH_TOKEN` | (empty) | Only for `authenticator=oauth` | OAuth access token from your IdP. Never logged or returned. Refresh via your IdP; restart the API after rotation. |
| `SNOWFLAKE_DATABASE` | `MDM_ETL_TRS` | No | Source database, derived from `SNOWFLAKE_SOURCE` (`MDM_ETL_<SOURCE>`) unless set explicitly. Holds the single `TRS_ETL_WRK` schema. |
| `SNOWFLAKE_SOURCE` | `TRS` | No | Source for this API instance. Drives the default database name (`MDM_ETL_<SOURCE>`); `MDM_ETL_COMMON` is shared across sources. One instance serves one source. |
| `SNOWFLAKE_SCHEMA` | `TRS_ETL_WRK` | No | The single schema in the source database. Inputs, IDQ rows, Snowflake rows, procedures, functions, views — all live here. |
| `SNOWFLAKE_COMMON_DATABASE` | `MDM_ETL_COMMON` | No | Framework database for COMMON (job control, metrics, shared functions). Not a copy destination. |
| `SNOWFLAKE_COMMON_SCHEMA` | `COMMON` | No | Framework schema inside `SNOWFLAKE_COMMON_DATABASE`. |
| `DISCRIMINATOR_COLUMN` | `DATA_SOURCE` | No | Pivotal column on target tables only. |
| `DISCRIMINATOR_IDQ_VALUE` | `IDQ` | No | Value the copy writes into `DATA_SOURCE` for IDQ rows. |
| `DISCRIMINATOR_SNOWFLAKE_VALUE` | `SNOWFLAKE` | No | Value the ETL writes (or the column default supplies) for Snowflake rows. |
| `SNOWFLAKE_WAREHOUSE` | (empty) | No — but see the warehouse note in §4.6 | Warehouse to use. Empty = default warehouse for the user/role. |
| `SNOWFLAKE_ROLE` | (empty) | No | Role to use. Empty = default role for the user. |
| `COPY_BATCH_SIZE` | `5000` | No | Rows per Oracle stream batch and Snowflake insert batch (§7). |
| `COMPARE_SAMPLE_LIMIT` | `20` | No | Default `sample_limit` for compare requests. A request's `sample_limit` overrides it (bounded 0–200). |
| `SQLITE_HARNESS_DB_PATH` | (empty) | No | File path for the persistent SQLite harness database. Only used by `GET /sqlite/tables`, which reads ONLY this file (no path parameter). Empty = that endpoint answers 404. |

**A note on "required".** Because engines are lazy, a missing
`ORACLE_USER` or `SNOWFLAKE_ACCOUNT` does not stop the API from
starting, and does not fail a plain `/health` or a dry-run copy.
It fails on the first real use, with a clear message naming the
missing setting (see `app/core/db.py`). That is intentional —
it is what makes dry runs and health checks work without
databases — but it means "the API started" is not evidence that
the configuration is complete. `GET /health?check_db=true` is.
