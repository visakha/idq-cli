# idq-cli User Guide - CLI Commands by Task

This guide shows how to drive the Java replacement of the Informatica IDQ Member-domain stage-load workflows from the
interactive shell (spring-shell) and from the REST API that mirrors it. It is organised by task: pick what you want to
do, follow the steps.

Contents

1. [Concepts in five minutes](#1-concepts-in-five-minutes)
2. [Start the CLI](#2-start-the-cli)
3. [Task: find out what is supported](#3-task-find-out-what-is-supported)
4. [Task: set your working context (latches)](#4-task-set-your-working-context-latches)
5. [Task: inspect a mapping and its data](#5-task-inspect-a-mapping-and-its-data)
6. [Task: prepare source data](#6-task-prepare-source-data)
7. [Task: run the ETL workflow](#7-task-run-the-etl-workflow)
8. [Task: review the audit reports and the mock-data SQL](#8-task-review-the-audit-reports-and-the-mock-data-sql)
9. [Task: run the unit tests](#9-task-run-the-unit-tests)
10. [Task: do all of it over REST](#10-task-do-all-of-it-over-rest)
11. [End-to-end walkthroughs](#11-end-to-end-walkthroughs)
12. [Configuration reference](#12-configuration-reference)
13. [Troubleshooting](#13-troubleshooting)
14. [Command quick reference](#14-command-quick-reference)
15. [Task: compare ORA_SP with IDQ](#15-task-compare-ora_sp-with-idq)

---

## 1. Concepts in five minutes

| Concept | What it means here |
|---|---|
| Source system | One of the five feeds: `TRS`, `ECI`, `FSS`, `TTF`, `WIC`. Each has its own IDQ workflow (`wf_*_Stage_Load`) and its own source tables (`STG_*`, `V_*`). |
| Domain / sub-domain | Everything implemented is in the `MEMBER` domain (`PROVIDER` is listed but not implemented). Sub-domains: Demographics, Phone-email, Address, Alternate-ID, Alternate-Name, Party-Managed-Attrib, Role. |
| Mapping | One IDQ mapping ported to Java, e.g. `m_Tgt_C_S_ECI_Pty_Rle_Rel`. 33 mappings in total; each has a document in `docs/mappings/NNN_<mapping>.md`. |
| Target table | The `C_S_*` staging table a mapping loads, e.g. `C_S_ECI_PTY_RLE_REL`. |
| IdqMapInitQuery | The first SQL a mapping runs to read its source rows. In Java it is a `@Query` method on the repository of the table it reads, returning a record, e.g. `EciFamilyDeltaRepository#fetchFamilyRelations` returning `EciQueryRows.FamilyRelation`. |
| Latch | The CLI's working context: one source system, optionally one target table and one mapping (plus one or more domains). Commands act on what is latched. |
| Engine (`etl_process`) | `JAVA` (default) runs the Java mappings; `IDQ` calls the Informatica `infacmd` script instead (simulated when `mock_infacmd=true`); `ORA_SP` calls the Oracle stored procedures of `idq-to-oracle/` over JDBC (simulated when `mock_ora_sp=true`). |
| Mock data | Synthetic source rows generated with Datafaker by `fill_sample_mock_data_<mapping>` functions. Controlled by `mock_data`, `idq.mock.rows-per-table` and `mock-data-pre-fix`. |
| Audit report | After every run, one Markdown file per target table in `adhoc_runs_<SOURCE>/` showing the source tables, the IdqMapInitQuery rows and the target rows, plus a `.sql` file that replays the mock data. |

The entity models behind the reports (all Spring Data JDBC records, no JPA):

| Kind | Class | Example |
|---|---|---|
| IdqMapInitQuery rows | records in `<Src>QueryRows` | `EciQueryRows.FamilyRelation` |
| Source tables and views | `<Src>Sources` | `EciSources.FamilyDelta` (`STG_ECI_D_FAMILY`) |
| Target tables | `mdmdc.etldb.models.<Src>Targets` | `EciTargets.Relationship` (`C_S_ECI_PTY_RLE_REL`) |
| MDM base tables | `MdmBaseTables` | `MdmBaseTables.PartyXref` (`C_B_PTY_XREF`) |
| Lookup / reference tables | `ReferenceTables` | `ReferenceTables.CodeValue` (`LOOKUP_CODE_VALUE`) |

Safety rules that always apply:

* **Nothing is ever deleted, truncated or dropped**, so the CLI is safe to point at production data. This holds for
  the whole code base: the Java mappings, the mock-data fills, `compare-etl-process` and the Oracle stored procedures
  of `idq-to-oracle/` that `etl_process=ORA_SP` calls. Rows are only inserted; the only DDL is `CREATE TABLE` for
  missing objects (`db/missing-objects.sql`, never `DROP` or `ALTER`).
* Consequence: the IDQ *Truncate target table* option and the `DD_DELETE` update strategies are **not** reproduced.
  A second run on the same source rows inserts the target rows again (or fails on a unique key). Empty the `C_S_*`
  targets yourself, outside this tool, when you need a clean load. Reactivated parties keep their row in
  `STG_<SRC>_PTY_INACTIVE_STS`, and `STG_TRS_VALID_MEMBERS` keeps deactivated members.
* Mock data is generated once: when a table already holds mock rows (mock id ranges `9100000001...`,
  `9200000001...` or rows marked `IDQ_CLI_MOCK`) they are kept and that table is not filled again.
* Never run `docs/*_EXPORT_OCT_16.sql`: those exports start with `DROP TABLE`.

---

## 2. Start the CLI

### Prerequisites

* JDK 27 at `C:\Users\vamsi\jdk\zulu27`, Maven 3.9 (or the bundled `mvnw`).
* The OCI wallet in `docs/wallet` (or `IDQ_WALLET_DIR`), user `ADMIN` (override with `IDQ_DB_USER` /
  `IDQ_DB_PASSWORD`).

```bat
set JAVA_HOME=C:\Users\vamsi\jdk\zulu27
set PATH=%JAVA_HOME%\bin;%PATH%
mvnw -q -DskipTests package
```

### Start the interactive shell

```bat
java -jar target\cli-0.0.1-SNAPSHOT.jar
```

or, from the sources, `mvnw -q spring-boot:run`. The REST API starts at the same time on port `8085`.

Properties are passed as JVM system properties, before `-jar`:

```bat
java -Detl_process=JAVA -Dmock_data=true -Dmock-data-pre-fix=Test_001 -jar target\cli-0.0.1-SNAPSHOT.jar
```

Do not pass `--name=value` after the jar; put every property as `-D...` before `-jar`.

JDK 27 prints a `WARNING: A restricted method in java.lang.foreign.MemorySegment has been called` block at start-up
(JLine terminal access). It is harmless; add `--enable-native-access=ALL-UNNAMED` before `-jar` to silence it.

### Scripted (non-interactive) use

Pipe the commands into the shell, one per line, ending with `exit`:

```bat
(echo latch-source-system ECI& echo run-etl& echo exit) | java -Dmock-data-pre-fix=Test_001 -jar target\cli-0.0.1-SNAPSHOT.jar
```

```bash
printf 'latch-source-system ECI\nrun-etl\nexit\n' | java -jar target/cli-0.0.1-SNAPSHOT.jar
```

For automation from other systems the REST API (section 10) is usually the better fit.

### The prompt

The prompt always shows the latched context, delimited by `+`, in the order source + target table + mapping:

```text
idq (no context)>                                   nothing latched
ECI>                                                source latched
ECI+C_S_ECI_PTY_RLE_REL>                            source and target table latched
ECI+C_S_ECI_PTY_RLE_REL+m_Tgt_C_S_ECI_Pty_Rle_Rel>  full context
```

It updates after every latch or unlatch command.

### Leave the shell

```text
idq (no context)> exit
```

`exit` also stops the REST API.

---

## 3. Task: find out what is supported

| Goal | Command |
|---|---|
| List the commands and what each one requires first | `show-menu` |
| Built-in help for every command (arguments, descriptions) | `help`, `help latch-mapping` |
| Domains, sub-domains and the mappings in each (all sources) | `show-domains` |
| Source systems, their workflow, source tables and target tables | `show-sources` |

`show-menu` also prints the active switches, e.g.
`Commands  ({etl_process=JAVA, mock_infacmd=true, mock_ora_sp=true, mock_data=true})`.
Each line shows `[requires ...]` for commands that need a latch first.

```text
idq (no context)> show-sources
TRS  wf_TRS_Stage_Load_1_Ongoing (TIERS eligibility system)
  source tables: [STG_TRS_D_DC_INDV, STG_TRS_D_CV_DC_MCI_INDV, ...]
  target tables: [C_S_TRS_PTY, C_S_TRS_PTY_RLE, C_S_TRS_PTY_MNG_ATTR, ...]
ECI  wf_ECI_Stage_Load (ECI child and family system)
  ...
```

---

## 4. Task: set your working context (latches)

Latches are applied top-down: a source system first, then a target table of that source, then a mapping that loads
that table. Domains are independent of the other latches.

### 4.1 Latch a source system

```text
idq (no context)> latch-source-system ECI
Latched source system ECI
ECI>
```

* Values: `TRS`, `ECI`, `FSS`, `TTF`, `WIC` (case-insensitive).
* Only one source system can be latched. Latching a different one clears the target table and mapping latches.
* Check it with `show-latched-source`; remove it with `unlatch-source-system` (clears everything below it too).

### 4.2 Latch domains (optional)

```text
ECI> latch-domain MEMBER
Latched domains [MEMBER]
ECI> show-latched-domains
[MEMBER]
ECI> unlatch-domain MEMBER
```

One or more domains can be latched at a time (`MEMBER`, `PROVIDER`).

### 4.3 Latch a target table

```text
ECI> latch-target-table C_S_ECI_PTY_RLE_REL
Latched target table C_S_ECI_PTY_RLE_REL
ECI+C_S_ECI_PTY_RLE_REL>
```

* Requires `latch-source-system`.
* Only the `C_S_*` targets of the latched source are accepted; a wrong name answers with the list of valid ones:
  `Not possible: C_S_TRS_PTY is not a target of ECI; choose one of [C_S_ECI_PTY, C_S_ECI_PTY_RLE, ...]`.
* Remove it with `unlatch-target-table` (also clears the mapping).

### 4.4 Find and latch a mapping

```text
ECI+C_S_ECI_PTY_RLE_REL> show-source-mapping
  018 m_Tgt_C_S_ECI_Pty_Rle_Rel                      Role           -> [C_S_ECI_PTY_RLE_REL]
ECI+C_S_ECI_PTY_RLE_REL> latch-mapping m_Tgt_C_S_ECI_Pty_Rle_Rel
Latched mapping m_Tgt_C_S_ECI_Pty_Rle_Rel
ECI+C_S_ECI_PTY_RLE_REL+m_Tgt_C_S_ECI_Pty_Rle_Rel>
```

* `show-source-mapping` lists the mappings that load the latched target: documentation number, mapping name,
  sub-domain and all tables the mapping writes. Some tables are loaded by more than one mapping (e.g.
  `C_S_TRS_PTY_MNG_ATTR` by `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` and `m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`).
* `latch-mapping` requires `latch-target-table` and accepts only a mapping from that list.
* Remove it with `unlatch-mapping`.

---

## 5. Task: inspect a mapping and its data

| Goal | How |
|---|---|
| Read the business logic of a mapping | Open `docs/mappings/NNN_<mapping>.md` (the number is the one `show-source-mapping` prints). Each document explains the IdqMapInitQuery in plain English with Mermaid diagrams, the Java classes, and lists the source entities. |
| See the first rows the mapping would read | `show-sample-data` (requires `latch-mapping`) |
| See everything the mapping read and wrote | Run the workflow and open its audit report (section 8). |

`show-sample-data` runs the latched mapping's IdqMapInitQuery against Oracle and prints up to 10 rows as records:

```text
ECI+C_S_ECI_PTY_RLE_REL+m_Tgt_C_S_ECI_Pty_Rle_Rel> show-sample-data
FamilyRelation[relationDirection=To Child, idFamily=9100000001, familyGender=F, idChild=9100000001, ...]
...
```

If the source tables are empty it answers `No source rows (try fill-sample-mock-data)`.

---

## 6. Task: prepare source data

There are three ways to get rows into the source tables. Pick one per run.

### 6.1 Generate mock data for one mapping

```text
ECI+C_S_ECI_PTY_RLE_REL+m_Tgt_C_S_ECI_Pty_Rle_Rel> fill-sample-mock-data
fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Rel: 20 rows per table generated
```

* Requires `latch-mapping` and `mock_data=true` (otherwise it answers `mock_data=false: mock data generation is
  disabled`).
* Calls `fill_sample_mock_data_<mapping>`: it first creates any missing source objects listed in
  `db/missing-objects.sql` (CREATE only), seeds the lookup tables (code values, exception catalog, area codes) and inserts
  `idq.mock.rows-per-table` rows per source table. A table that already holds mock rows from an earlier fill is left
  as it is (nothing is deleted), so the mock rows stay the same from run to run. To get fresh mock rows, remove the
  old ones yourself, outside this tool.
* A few rows are invalid on purpose (missing first name, future birth date, unknown codes, malformed e-mail or phone)
  so that the bad-data paths to `EXC_STG_BAD_REC_MEMB` are exercised.

You do not need this command before `run-etl`: with `mock_data=true`, `run-etl` fills the mock data of every mapping of
the source by itself (section 7).

### 6.2 Mark mock data with a prefix (`mock-data-pre-fix`)

Set the property to make every generated free-text value recognisable:

```bat
java -Dmock-data-pre-fix=Test_001 -jar target\cli-0.0.1-SNAPSHOT.jar
```

With `mock-data-pre-fix=Test_001`, `STG_TRS_D_DC_CASES.EMAIL` becomes `Test_001-JaneDoe@gmail.com`.

| Prefixed (free text) | Never prefixed |
|---|---|
| First, middle (TRS) and last names | Codes and lookups: gender, race, ethnicity, language, state, country, address/phone/alternate-id types, program and status codes |
| E-mail addresses | Reference data seeded into the lookup tables (code values, exception catalog, area codes) |
| Address lines and street names | Keys and identifiers: individual, case, family and client ids, `PTY_PK`, `PTY_SRC_KEY` |
| City and county names | Formatted numbers the ETL validates: phone numbers, SSN, Medicaid number, ZIP codes, provider TPI |
| | Deliberate junk values such as the TTF first name `DECLINED`, one-letter ECI middle initials |

Notes:

* The prefix and a hyphen are put in front: `<prefix>-<value>`.
* If the prefixed value is longer than the column (for example ECI `FIRST_NAME` is 20 characters), the end of the
  original value is cut so that the prefix always survives: `Test_001-Christopher` in a 15-character column becomes
  `Test_001-Christ`.
* Leave the property empty (default) for no prefix.
* `run-etl` prints the prefix in its first line: `mock_data=true: 20 rows per table generated by ... (mock-data-pre-fix=Test_001)`.

### 6.3 Use your own rows

1. Start with `-Dmock_data=false`, so `run-etl` does not generate anything.
2. Insert your rows into the source tables of the mapping (`show-sources` lists them; the mapping document and the
   `<Src>Sources` entities show every column).
3. Run the workflow (section 7).

Tip: the `.sql` file next to every audit report (section 8) is a ready-made script of mock rows. Copy it, edit the
values and run it in SQL Developer as a starting point for your own test data.

### 6.4 Real sample data (placeholder)

`fill-sample-real-data` (requires `latch-mapping`) calls `fill_sample_real_data_<mapping>`. The functions are empty
placeholders for now and answer `... not implemented yet (placeholder)`.

---

## 7. Task: run the ETL workflow

```text
ECI> run-etl
Workflow wf_ECI_Stage_Load (JAVA)
mock_data=true: 20 rows per table generated by fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Validation, ...
m_Tgt_C_S_ECI_Pty_Validation                     SUCCEEDED read=40     written={STG_ECI_PTY_INACTIVE_LOG=1, ...} exceptions=1 (527 ms)
m_Tgt_C_S_ECI_Pty                                SUCCEEDED read=40     written={C_S_ECI_PTY=39, C_S_ECI_PTY_RLE=39, ...} exceptions=4 (615 ms)
...
Audit reports: C:\Users\vamsi\wrk-java\idq-cli\adhoc_runs_ECI
```

What happens:

1. Requires `latch-source-system` only. Target table and mapping latches do not limit the run.
2. With `mock_data=true`, the mock data of every mapping of the source is generated first (section 6.1).
3. With `etl_process=JAVA`, every mapping of the workflow runs in IDQ workflow order. For each one: read the
   IdqMapInitQuery, apply the transformation, write the targets in one transaction. A failing mapping is reported as
   `FAILED` with its error and the workflow carries on, because mappings whose sources are empty or unrelated to what
   you are testing should not stop the run.
4. With `etl_process=IDQ`, the Informatica workflow is started through `idq.infacmd.script`
   (`infacmd wfs startWorkflow`). With `mock_infacmd=true` the call is only simulated and its output printed.
5. With `etl_process=ORA_SP`, the Oracle stored procedures that replace the mappings (`sp_ors_main_<mapping>`, see
   `idq-to-oracle/README.md`) are called over JDBC, one `BEGIN ...; END;` per procedure, in the order of the
   workflow's run script `<idq.ora-sp.dir>/<workflow>/run_<workflow>.sql`. That script also lists procedures that
   have no Java mapping (the ECI reactivation mappings, the TRS deactivation mappings); they are called and shown in
   the output but have no audit report. Each procedure commits on its own. The first failure stops the run, and the
   procedures after it are shown as `SKIPPED`, as `WHENEVER SQLERROR EXIT` does in the script. With
   `mock_ora_sp=true` nothing is executed and each result line says `[mock] EXEC sp_ors_main_...`. The procedures
   must be installed first (`@install.sql` in `idq-to-oracle/`).
6. The audit reports are written (section 8); the last line gives their directory.

Result line per mapping: status, rows read by the IdqMapInitQuery, rows written per table (including the bad-data
table `EXC_STG_BAD_REC_MEMB`), number of data-quality exceptions and elapsed time.

Workflow order (documentation numbers):

| Source | Order |
|---|---|
| TRS | 001, 007, 002, 003, 004, 005, 006, 008, 009, 010, 011, 012 |
| ECI | 013 validation, 014 party, then 015-018 |
| FSS | 019 validation, 020 party, then 021-024 |
| TTF | 025 validation, 026 party, then 027-028 |
| WIC | 029 validation, 030 party, then 031-033 |

Running a single mapping is available over REST only: latch the mapping, then `POST /api/etl/run/mapping` (section 10).

---

## 8. Task: review the audit reports and the mock-data SQL

Every run writes, for each table loaded by the run's mappings (the `C_S_*` targets and side tables such as
`DQM_ADDRESS` or `STG_ECI_PTY_INACTIVE_STS`):

```text
adhoc_runs_ECI\C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_10_58_AM.md     audit report
adhoc_runs_ECI\C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_10_58_AM.sql    mock data of that report
```

* Directory: `<idq.report.base-dir>/adhoc_runs_<SOURCE>` (base dir defaults to the working directory).
* Name: `<TABLE>_$<Java|IDQ|ORA_SP>$_<dd_MM_yyyy_h_mm_AM|PM>`. A second run in the same minute adds `_2`, `_3`, ...
* The `$` signs are part of the name: quote it in a shell, e.g. `type "adhoc_runs_ECI\C_S_ECI_PTY_$Java$_19_10_2026_10_58_AM.md"`.
* The reports are produced by Spring events (`EtlEvent`) published during the run and written by the
  `AdhocRunReporter` listener; switch them off with `idq.report.enabled=false`.

### What the Markdown report contains

1. Run header: source system and workflow, `etl_process`, start time, rows shown per table, the name of the `.sql`
   file (or `none` when no mock data was generated for these mappings).
2. One summary row per mapping that loads the table: status, rows read, rows written, exceptions, time, error
   message.
3. Per mapping:
   * **Source tables** - each table or view the mapping reads, as captured just before it ran, through its source
     entity (e.g. `EciSources.FamilyDelta`): total rows and the first `idq.report.max-rows` rows.
   * **IdqMapInitQuery** - the rows the mapping's first SQL returned, through its record (e.g.
     `EciQueryRows.FamilyRelation`).
   * **Target** - the rows this run loaded into the table, read back from Oracle by `PKEY_SRC_OBJECT` through the
     target entity (e.g. `EciTargets.Relationship`). With `etl_process=IDQ`: the table content after the workflow.
     With `etl_process=ORA_SP`: the table content after the mapping's stored procedure.
   * **EXC_STG_BAD_REC_MEMB** - the data-quality exceptions the mapping raised, when there are any.

Column headers are the database column names; values are plain ASCII.

### What the SQL file contains

The statements that generated the mock data behind the report, in the order they ran, with literal values:

```sql
-- Mock source data behind the C_S_ECI_PTY_RLE_REL report of the ECI Java run started 2026-10-19 10:58:34
-- mock-data-pre-fix: Test_001
-- Replays the mock fills: these rows are inserted (nothing is deleted).
-- Run it in the OCI schema, then run-etl with mock_data=false to process exactly these rows.

-- reference data (ReferenceMockData.seed)
INSERT INTO LOOKUP_CODE_VALUE (...) VALUES (...);
...

-- fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Rel
INSERT INTO STG_ECI_D_FAMILY (ID_FAMILY, ID_CHILD, FAMILY_CD, GENDER, FIRST_NAME, ...) VALUES (9100000001, 9100000001, 1, 'F', 'Test_001-Mia', ...);
...

COMMIT;
```

* Written only when mock data was generated (by `run-etl` with `mock_data=true` or by `fill-sample-mock-data`) for
  at least one mapping of the report. Each mock fill is reported once: the next run without new mock data gets no
  `.sql`.
* Replaying the script inserts exactly the rows of that run: run it in a schema that does not hold them yet, then
  `run-etl` with `-Dmock_data=false`.
* Only the rows actually inserted are in the script: a table whose mock rows already existed is not filled again and
  does not appear.
* The objects of `db/missing-objects.sql` must exist (the application creates them on its first mock fill).

---

## 9. Task: run the unit tests

### From the shell

```text
ECI+C_S_ECI_PTY_RLE_REL+m_Tgt_C_S_ECI_Pty_Rle_Rel> run-unit-tests
mvnw.cmd -q test -Dtest=EciPkeyTest#m_Tgt_C_S_ECI_Pty_Rle_Rel_pkey_test
exit code 0
```

Requires `latch-mapping`. Runs the PKEY test of the latched mapping (`<Src>PkeyTest#<mapping>_pkey_test`, verifies the
`PKEY_SRC_OBJECT` formulation) through the Maven wrapper of the current directory, so start the CLI from the project
directory. Exit code `0` means the test passed.

### From the command line

```bat
mvnw test                                                    all unit tests, no database needed
mvnw test -Dtest=EciPkeyTest                                 the PKEY tests of one source
mvnw test -Dtest=OracleWorkflowIT                            all 33 mappings against OCI on mock data
mvnw test -Dtest=OracleWorkflowIT#runWritesAuditReports -Dsource=TRS
mvnw test -Dtest=SourceEntitiesIT                            every source / MDM / reference entity against OCI
```

`SourceEntitiesIT` inserts one row per entity record, counts it and reads it back, then rolls back, so the
schema is left untouched. `OracleWorkflowIT` and `SourceEntitiesIT` are not part of `mvnw test` (their names do
not match the test pattern) and need the wallet and network access; `runWritesAuditReports` runs one whole workflow
with `mock-data-pre-fix=Test_001` and checks its reports and SQL files in `target/adhoc-it`.

---

## 10. Task: do all of it over REST

The REST API runs on `http://localhost:8085/api/etl` while the shell is open. Latches are shared: a latch set over
REST shows up in the shell prompt and vice versa. Errors (missing latch, wrong name) return HTTP 400 with
`{"message": "..."}`.

| CLI command | HTTP |
|---|---|
| `show-menu` | `GET /api/etl/menu` |
| `show-domains` | `GET /api/etl/domains` |
| `show-sources` | `GET /api/etl/sources` |
| `latch-source-system X` | `POST /api/etl/latch/source/X` |
| `unlatch-source-system` | `DELETE /api/etl/latch/source` |
| `show-latched-source`, `show-latched-domains` | `GET /api/etl/latch` |
| `latch-domain X` | `POST /api/etl/latch/domain/X` |
| `unlatch-domain X` | `DELETE /api/etl/latch/domain/X` |
| `latch-target-table X` | `POST /api/etl/latch/target/X` |
| `unlatch-target-table` | `DELETE /api/etl/latch/target` |
| `show-source-mapping` | `GET /api/etl/source-mappings` |
| `latch-mapping X` | `POST /api/etl/latch/mapping/X` |
| `unlatch-mapping` | `DELETE /api/etl/latch/mapping` |
| `show-sample-data` | `GET /api/etl/sample-data?limit=10` |
| `fill-sample-mock-data` | `POST /api/etl/sample-data/mock` |
| `fill-sample-real-data` | `POST /api/etl/sample-data/real` |
| `run-etl` | `POST /api/etl/run` |
| (single mapping, REST only) | `POST /api/etl/run/mapping` |
| `run-unit-tests` | `POST /api/etl/unit-tests` |
| `compare-etl-process X` | `POST /api/etl/compare/X` (`X` = name or 1-5; returns the comparison as JSON) |

Example session with curl:

```bat
curl -X POST http://localhost:8085/api/etl/latch/source/ECI
curl -X POST http://localhost:8085/api/etl/latch/target/C_S_ECI_PTY_RLE_REL
curl http://localhost:8085/api/etl/source-mappings
curl -X POST http://localhost:8085/api/etl/latch/mapping/m_Tgt_C_S_ECI_Pty_Rle_Rel
curl -X POST http://localhost:8085/api/etl/sample-data/mock
curl -X POST http://localhost:8085/api/etl/run/mapping
curl -X POST http://localhost:8085/api/etl/run
curl http://localhost:8085/api/etl/latch
```

`GET /api/etl/latch` returns the context string shown in the prompt plus each latch:
`{"context":"ECI+C_S_ECI_PTY_RLE_REL+m_Tgt_C_S_ECI_Pty_Rle_Rel","source":"ECI",...}`.

From Java, `com.idq.cli.api.EtlApiClient` (a `RestClient`) wraps the same endpoints: `latchSource("ECI")`,
`latchTarget(...)`, `latchMapping(...)`, `fillMock()`, `runEtl()`, `runUnitTests()`.

Single-mapping runs (`/run/mapping`) write audit reports too, for that one mapping.

---

## 11. End-to-end walkthroughs

### 11.1 Quick look at a whole workflow on mock data

```text
java -Dmock-data-pre-fix=Test_001 -jar target\cli-0.0.1-SNAPSHOT.jar
idq (no context)> latch-source-system ECI
ECI> run-etl
ECI> exit
```

Open `adhoc_runs_ECI\C_S_ECI_PTY_$Java$_<time>.md` to see the child and family rows (`Test_001-...` names) going into
`C_S_ECI_PTY`, and the `.sql` next to it for the mock rows.

### 11.2 Investigate one mapping

```text
idq (no context)> latch-source-system TRS
TRS> latch-target-table C_S_TRS_PTY_RLE_PHN
TRS+C_S_TRS_PTY_RLE_PHN> show-source-mapping
TRS+C_S_TRS_PTY_RLE_PHN> latch-mapping m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr
TRS+C_S_TRS_PTY_RLE_PHN+m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr> fill-sample-mock-data
TRS+C_S_TRS_PTY_RLE_PHN+m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr> show-sample-data
TRS+C_S_TRS_PTY_RLE_PHN+m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr> run-unit-tests
TRS+C_S_TRS_PTY_RLE_PHN+m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr> run-etl
```

Then read `docs/mappings/006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md` next to
`adhoc_runs_TRS\C_S_TRS_PTY_RLE_PHN_$Java$_<time>.md`: the malformed phone numbers and e-mails of the mock rows show up
under `EXC_STG_BAD_REC_MEMB`.

### 11.3 Test with your own rows

1. Take the `.sql` of an earlier report (or write your own `INSERT`s into the source tables).
2. Run it in SQL Developer against the OCI schema.
3. Start the CLI with `-Dmock_data=false`, `latch-source-system <SRC>`, `run-etl`.
4. The report shows exactly your rows in the source tables, what the IdqMapInitQuery picked up and what reached the
   `C_S_*` tables.

### 11.4 Compare with Informatica

1. Start with `-Detl_process=IDQ -Dmock_infacmd=false` on a machine with `infacmd` (adjust `idq.infacmd.*`).
2. `latch-source-system TRS`, `run-etl`: the Informatica workflow runs; the reports (`$IDQ$` in the name) show the
   sources and IdqMapInitQuery rows before the run and the target tables after it.
3. Run the same data with `-Detl_process=JAVA -Dmock_data=false` and compare the two `C_S_*` sections.

### 11.5 Compare with the Oracle stored procedures

For ORA_SP against IDQ, use `compare-etl-process` (section 15): it runs both engines on the same data and writes
the comparison for you. The steps below compare ORA_SP with the Java engine.

1. Install the procedures in the OCI schema: `@install.sql` from `idq-to-oracle/` (see its README).
2. Start with `-Detl_process=ORA_SP -Dmock_ora_sp=false`.
3. `latch-source-system ECI`, `run-etl`: every `sp_ors_main_*` of `run_wf_ECI_Stage_Load.sql` runs in order; the
   reports (`$ORA_SP$` in the name) show the sources and IdqMapInitQuery rows before each procedure and the target
   tables after it.
4. Run the same data with `-Detl_process=JAVA -Dmock_data=false` (or `IDQ`) and compare the `C_S_*` sections.

---

## 12. Configuration reference

Set in `src/main/resources/application.properties` or as `-Dname=value` before `-jar`.

| Property | Default | Meaning |
|---|---|---|
| `etl_process` | `JAVA` | `JAVA` runs the Java mappings, `IDQ` runs the Informatica workflow via `infacmd`, `ORA_SP` calls the Oracle stored procedures |
| `mock_infacmd` | `true` | With `IDQ`: print the simulated `infacmd` call instead of running `idq.infacmd.script` |
| `mock_ora_sp` | `true` | With `ORA_SP`: report each `EXEC sp_ors_main_*` instead of calling it |
| `idq.ora-sp.dir` | `idq-to-oracle` | Folder with `<workflow>/run_<workflow>.sql`, which gives the procedures and their order (ORA_SP engine) |
| `mock_data` | `true` | Allow mock data; `run-etl` generates it for every mapping before the run |
| `idq.mock.rows-per-table` | `20` | Mock rows per source table |
| `mock-data-pre-fix` | (empty) | Prefix for free-text mock values, e.g. `Test_001` gives `Test_001-JaneDoe@gmail.com` |
| `idq.report.enabled` | `true` | Write the audit reports and SQL files |
| `idq.report.base-dir` | `.` | Directory that holds the `adhoc_runs_<SOURCE>` folders |
| `idq.report.max-rows` | `200` | Rows shown per table in a report (at most 1000; totals are always given) |
| `idq.bootstrap-missing-objects` | `true` | Create (never drop) the objects of `db/missing-objects.sql` that do not exist |
| `idq.infacmd.script` | `docs/batch-script-windows.original.bat` | Script that calls `infacmd` (IDQ engine) |
| `idq.infacmd.domain`, `.service`, `.application` | `Domain_Prod`, `DIS_DataQuality`, `App_ETL_Master` | `infacmd wfs startWorkflow` arguments |
| `idq.wallet-dir` / `IDQ_WALLET_DIR` | `docs/wallet` | OCI wallet directory (TNS alias `oci4idq_low`) |
| `IDQ_DB_USER`, `IDQ_DB_PASSWORD` | `ADMIN`, (set) | Database credentials |
| `idq.compare.ignore-columns` | `ROWID_OBJECT,CREATE_DATE,LAST_UPDATE_DATE,CREATOR,UPDATED_BY,PERIOD_START_DATE,PERIOD_END_DATE` | `compare-etl-process`: columns left out of the target comparison |
| `server.port` | `8085` | REST API port |

---

## 13. Troubleshooting

| Message or symptom | Cause and fix |
|---|---|
| `Not possible: latch-source-system first` | The command needs a source system: `latch-source-system <SRC>`. |
| `Not possible: latch-target-table first` | `show-source-mapping` and `latch-mapping` need a target table. |
| `Not possible: latch-mapping first` | `show-sample-data`, `fill-sample-*`, `run-unit-tests` need a mapping. |
| `Not possible: X is not a target of SRC; choose one of [...]` | Pick a table from the list (or from `show-sources`). |
| `Not possible: X does not load the latched target; choose one of [...]` | Pick a mapping printed by `show-source-mapping`. |
| `Not possible: No enum constant ...SourceSystem.X` | Unknown source system; use `TRS`, `ECI`, `FSS`, `TTF` or `WIC`. |
| `No source rows (try fill-sample-mock-data)` | The source tables are empty: generate mock data or insert rows. |
| `mock_data=false: mock data generation is disabled` | Start with `-Dmock_data=true` to generate mock rows. |
| A mapping or procedure fails with `ORA-00001: unique constraint` on a `C_S_*` table | The target still holds the rows of an earlier run: nothing is truncated any more. Empty the target yourself, outside this tool, if a reload is intended. |
| The target holds every row twice after a second run | Same cause: loads only insert. Empty the targets yourself before a reload. |
| `fill-sample-mock-data` / `run-etl` did not change the mock rows | Mock rows already present are kept, never deleted and regenerated. Remove them yourself to get fresh ones. |
| A mapping shows `FAILED` with an `ORA-` error | Check the source objects exist (`idq.bootstrap-missing-objects=true` creates the missing ones on the next mock fill) and the wallet / network. |
| `Cannot read the ORA_SP run script ...` | `etl_process=ORA_SP` needs `<idq.ora-sp.dir>/<workflow>/run_<workflow>.sql`; start the CLI from the project directory or set `-Didq.ora-sp.dir`. |
| A procedure shows `FAILED ... PLS-00201` / `ORA-06550` | The procedure is not installed (or not valid) in the schema: run `@install.sql` from `idq-to-oracle/`. `ORA-20999` means the `fn_dq_*` contract stubs are installed instead of the real functions. |
| A report section says `could not be read: ...` | That table could not be queried; the run itself is unaffected. The message names the cause. |
| A property seems ignored | Pass it before `-jar` (`java -Dname=value -jar ...`), not after. |
| `type adhoc_runs_ECI\C_S_...$Java$...md` finds nothing | Quote the file name; the `$` signs are part of it. |
| No `.sql` next to a report | No mock data was generated for those mappings since their last report (e.g. `mock_data=false`). |
| `compare-etl-process` warns `mock_ora_sp=true` / `mock_infacmd=true` | One or both engines were only simulated, so the comparison means nothing. Start with `-Dmock_ora_sp=false -Dmock_infacmd=false`. |
| `compare-etl-process` reports a source table `changed by ORA_SP` / `changed by IDQ` | That engine wrote to a table the workflow reads. Nothing is restored (the CLI never deletes); check whether the table should be a target. |
| `compare-etl-process` target shows `ERROR` | The table could not be read after a run (missing table, privileges); the message is in the report. |
| `run-unit-tests` exit code not 0 | Read the printed Maven output; start the CLI from the project directory so `mvnw` is found. |

---

## 14. Command quick reference

| Command | Arguments | Requires | Does |
|---|---|---|---|
| `show-menu` | | | Commands, prerequisites and active switches |
| `help` | `[command]` | | Built-in spring-shell help |
| `show-domains` | | | Domains, sub-domains and mappings |
| `show-sources` | | | Source systems, workflows, source and target tables |
| `latch-source-system` | `TRS\|ECI\|FSS\|TTF\|WIC` | | Latch the source system (clears target and mapping when it changes) |
| `unlatch-source-system` | | | Clear source, target table and mapping |
| `show-latched-source` | | | Show the latched source system |
| `latch-domain` | `MEMBER\|PROVIDER` | | Add a domain |
| `unlatch-domain` | `MEMBER\|PROVIDER` | | Remove a domain |
| `show-latched-domains` | | | Show the latched domains |
| `latch-target-table` | `C_S_*` table | source | Latch a target table of the source |
| `unlatch-target-table` | | | Clear target table and mapping |
| `show-source-mapping` | | target table | Mappings that load the latched table |
| `latch-mapping` | mapping name | target table | Latch a mapping |
| `unlatch-mapping` | | | Clear the mapping |
| `show-sample-data` | | mapping | First 10 IdqMapInitQuery rows |
| `fill-sample-mock-data` | | mapping | Generate mock source rows for the mapping |
| `fill-sample-real-data` | | mapping | Placeholder for real sample rows |
| `run-etl` | | source | Mock fill (if enabled), run the workflow, write the audit reports |
| `run-unit-tests` | | mapping | PKEY unit test of the mapping |
| `compare-etl-process` | `[TRS\|ECI\|FSS\|TTF\|WIC\|1-5]` (prompted when omitted) | | Run ORA_SP then IDQ on the same source data, compare the target tables, write `compare_runs_<SOURCE>/*.md` |
| `exit` | | | Leave the shell and stop the REST API |

---

## 15. Task: compare ORA_SP with IDQ

`compare-etl-process` answers one question: given the same source rows, do the Oracle stored procedures
(`etl_process=ORA_SP`) and the Informatica workflow (`etl_process=IDQ`) leave the same rows in the target tables?

### 15.1 Run it

Start the CLI with both engines live (otherwise the comparison only compares two simulations and says so in a
warning):

```bat
java -Dmock_ora_sp=false -Dmock_infacmd=false -jar target\cli-0.0.1-SNAPSHOT.jar
```

Then run the command. Without an argument it lists the source systems and asks which one to compare:

```text
idq (no context)> compare-etl-process
Compare etl-process ORA_SP vs IDQ (no mock data; the source tables are left unchanged).
Source systems:
  1) TRS  wf_TRS_Stage_Load_1_Ongoing (TIERS eligibility system)
  2) ECI  wf_ECI_Stage_Load (ECI child and family system)
  3) FSS  wf_FSS_Stage_Load (FSS source system)
  4) TTF  wf_TTF_Stage_Load (TTF source system)
  5) WIC  wf_WIC_Stage_Load (Women, Infants and Children)
Choose a source system [1-5]: 2
ORA_SP vs IDQ for ECI (wf_ECI_Stage_Load): target tables DIFFER
  C_S_ECI_PTY                  SAME ORA_SP=39 IDQ=39 matched=39 onlyORA_SP=0 onlyIDQ=0 changed=0
  C_S_ECI_PTY_RLE_ADDR         DIFF ORA_SP=31 IDQ=30 matched=28 onlyORA_SP=1 onlyIDQ=0 changed=2
  ...
Comparison report: C:\Users\vamsi\wrk-java\idq-cli\compare_runs_ECI\ECI_ORA_SP_vs_IDQ_21_10_2026_9_05_AM.md
```

* Answer with the number or the name (`2` or `ECI`). If a source system is latched, Enter picks it.
* Skip the prompt by giving the source directly: `compare-etl-process ECI` (or `compare-etl-process 2`). Use this form
  in scripts piped into the shell.
* No latch is needed, and no latch is changed.
* Over REST: `POST /api/etl/compare/ECI` returns the same comparison as JSON.

### 15.2 What it does

1. **No mock data.** Unlike `run-etl`, nothing is generated: both engines read the source tables as they are. Load
   the rows you want to compare first (section 6.3).
2. **Snapshot.** Every table the workflow reads (the source tables listed by `show-sources` and the tables and
   views each mapping reads, including the `C_B_*` and lookup tables) and every table it loads is read in full.
3. **ORA_SP.** The `sp_ors_main_*` procedures run in the order of `run_<workflow>.sql`, exactly as `run-etl` does
   with `etl_process=ORA_SP` (the first failure stops the procedures that follow). The target tables are read
   in full again. The **ORA_SP result** of a table is the rows added since step 2 (the procedures only insert).
4. **IDQ.** The Informatica workflow is started through `idq.infacmd.script`, as `run-etl` does with
   `etl_process=IDQ`. The script polls `getWorkflowStatus` and returns only when the workflow has finished, so the
   command waits for it. The target tables are read in full again. The **IDQ result** is the rows added since step
   3. If rows that were there after step 3 are gone, the Informatica target is set to *Truncate target table*
   (Informatica does that itself; this tool never does); the whole table is then the IDQ result, and the report
   notes it.
5. **Source check.** The source tables are compared with the step-2 snapshot: the report shows, per table, whether
   either engine changed it. Nothing is ever put back: the command only reads (`SELECT`), it never deletes.
6. **Compare and report.** Each target table is compared (section 15.3) and the report is written.

Both runs also write their usual audit reports (`adhoc_runs_<SOURCE>/..._$ORA_SP$_...` and `..._$IDQ$_...`, section
8).

Be aware:

* The command needs the procedures installed (`@install.sql` in `idq-to-oracle/`) and a machine where `infacmd`
  works (`idq.infacmd.*`).
* Tables are held in memory while the command runs. Very large source tables (e.g. a full `C_B_PTY_XREF`) make it slow
  and memory hungry.
* Both engines read the same source rows because neither the command nor the procedures change the source
  tables. The source-table check in the report confirms it for each run.
* Both engines write into the same target tables, one after the other. Because nothing is truncated, a unique key on
  a `C_S_*` table can make the second engine fail when it inserts the same keys. Empty the targets yourself before the
  command if that happens.

### 15.3 How rows are compared

* All columns take part except `idq.compare.ignore-columns` (default: `ROWID_OBJECT`, `CREATE_DATE`,
  `LAST_UPDATE_DATE`, `CREATOR`, `UPDATED_BY`, `PERIOD_START_DATE`, `PERIOD_END_DATE`), which differ on every run.
* Values are normalised before comparing: numbers without trailing zeros (`1.50` = `1.5`), dates and timestamps to the
  second, `NULL` as empty.
* Rows are matched as a multiset: a row identical in both results counts as *matched*, duplicates included.
* In tables with `PKEY_SRC_OBJECT`, an unmatched ORA_SP row and an unmatched IDQ row with the same key are a
  *changed* row; the report lists every column whose value differs. The remaining unmatched rows are *only in ORA_SP*
  or *only in IDQ*.
* A table is `SAME` when both results hold the same number of rows and every row is matched.

### 15.4 The report

`<idq.report.base-dir>/compare_runs_<SOURCE>/<SOURCE>_ORA_SP_vs_IDQ_<dd_MM_yyyy_h_mm_AM|PM>.md` (a second run in the
same minute adds `_2`, `_3`, ...). It contains:

1. Header: source and workflow, start time, overall result (`target tables MATCH` / `target tables DIFFER`), the
   mock switches, how each result is taken, the ignored columns.
2. Warnings: simulated engines, a failed procedure, a source table that changed.
3. **Target tables**: one line per table with the row counts of each engine, matched, only-ORA_SP, only-IDQ and
   changed keys, and `SAME` / `DIFF` / `ERROR`.
4. **Source tables (must be unchanged)**: rows before, after ORA_SP and after IDQ, and whether the table changed;
   then **Notes**: the tables whose IDQ (or ORA_SP) result is the whole table because that engine emptied it.
5. **Runs**: the output of the ORA_SP run (one line per procedure) and of the IDQ run (the `infacmd` output).
6. One section per table that differs: the changed rows (key, column, ORA_SP value, IDQ value), then the rows only in
   ORA_SP and the rows only in IDQ, up to `idq.report.max-rows` rows each.
