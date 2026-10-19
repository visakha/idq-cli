use the JDK in the folder  C:\Users\vamsi\jdk\zulu27
set the environment and maven pointers accordingly

see the instructions-for-rewrite.md

# idq-cli

A Spring Boot 4 / Java 27 replacement for the Informatica IDQ stage-load workflows of the Member domain
(`docs/wf_*.xml`: TRS, ECI, FSS, TTF, WIC; 33 mappings). Spring Data JDBC only, with a spring-shell CLI and a REST API
that mirrors it.

* User guide (CLI and REST, by task): [user-guide-cli.md](user-guide-cli.md).
* Mapping documentation: [docs/mappings/README.md](docs/mappings/README.md), one `NNN_<mapping>.md` per mapping.
* Code layout: `domain` (interfaces per sub-domain), `source/<sys>` (one class per mapping, named queries in
  `<Sys>Queries`, targets in `<Sys>Targets`), `core` (mapplets, rules, target structure, Informatica functions),
  `workflow`, `cli`, `api`, `mock`.

## Build and test

```bat
set JAVA_HOME=C:\Users\vamsi\jdk\zulu27
set PATH=%JAVA_HOME%\bin;C:\Users\vamsi\apps\mvn-3.9.9\bin;%PATH%
mvn test
```

`mvn test` runs one PKEY unit test per mapping (`<Src>PkeyTest#<mapping>_pkey_test`) without a database.
The end-to-end run against OCI Oracle is `OracleWorkflowIT` (mock data, all 33 mappings):

```bat
mvn test -Dtest=OracleWorkflowIT
mvn test -Dtest=OracleWorkflowIT -Dmappings=m_Tgt_C_S_TTF_Pty,m_Tgt_C_S_TTF_Pty_Rle_Phn
```

## CLI

```bat
mvn -q spring-boot:run
java -Detl_process=JAVA -jar target\cli-0.0.1-SNAPSHOT.jar
```

Properties go on the command line as `-D...` before `-jar` (not `--prop=...`, which spring-shell reads as a
command). The prompt shows the latched context, e.g. `TRS+C_S_TRS_PTY+m_Tgt_C_S_TRS_Pty_OnGoing>`.

| Command | Purpose |
|---|---|
| `show-menu` | Commands and their prerequisites |
| `show-domains`, `latch-domain`, `unlatch-domain`, `show-latched-domains` | Domain context |
| `show-sources`, `latch-source-system`, `unlatch-source-system`, `show-latched-source` | Source system context |
| `latch-target-table`, `unlatch-target-table` | `C_S_*` target of the latched source |
| `show-source-mapping`, `latch-mapping`, `unlatch-mapping` | Mappings that load the latched target |
| `show-sample-data` | Sample rows of the latched mapping's IdqMapInitQuery |
| `fill-sample-mock-data` | Faker rows via `fill_sample_mock_data_<mapping>` |
| `fill-sample-real-data` | Placeholder (`RealSampleData`) |
| `run-etl` | Whole workflow of the latched source (mock rows first when `mock_data=true`), then audit reports |
| `run-unit-tests` | PKEY unit test of the latched mapping |

## Entity models and audit reports

Every table has a Spring Data JDBC `@Table` record (no JPA):

| Kind | Where | Example |
|---|---|---|
| `IdqMapInitQuery` rows | records next to their `@Query` in `<Src>Queries` | `EciQueries.FamilyRelation` |
| Source tables / views | `<Src>Sources` | `EciSources.DFamily` (`STG_ECI_D_FAMILY`) |
| Target `C_S_*` tables | `<Src>Targets` | `EciTargets.Relationship` (`C_S_ECI_PTY_RLE_REL`) |
| MDM base tables | `MdmBaseTables` | `MdmBaseTables.PartyXref` (`C_B_PTY_XREF`) |

`MappingInfo.sourceEntities` lists the source entities of each mapping. During a run `EtlAudit` publishes Spring
events (`EtlEvent`): source tables before each mapping, the `IdqMapInitQuery` rows, and the target rows read back by
`PKEY_SRC_OBJECT` (with `etl_process=IDQ`: the target tables after the workflow). `AdhocRunReporter` listens and
writes one Markdown file per target table, e.g. `adhoc_runs_ECI/C_S_ECI_PTY_RLE_$Java$_19_10_2026_9_54_AM.md`,
plus a `.sql` with the same name holding the statements that generated the run's mock data.
Quote the name in a shell because of the `$` signs.

## REST API

Port `8085`, base path `/api/etl`; every CLI command has an endpoint (table in `EtlController`). `EtlApiClient` is a
`RestClient` based client for the same endpoints.

## Configuration (`application.properties`)

| Property | Default | Meaning |
|---|---|---|
| `etl_process` | `JAVA` | `JAVA` runs the ported mappings, `IDQ` runs `infacmd` |
| `mock_infacmd` | `true` | With `IDQ`, log the infacmd call instead of running `idq.infacmd.script` |
| `mock_data` | `true` | `run-etl` fills every mapping's source tables with mock rows before the run |
| `idq.mock.rows-per-table` | `20` | Mock rows per source table |
| `mock-data-pre-fix` | (empty) | Prefix for free-text mock values: `Test_001` gives `Test_001-JaneDoe@gmail.com` |
| `idq.bootstrap-missing-objects` | `true` | Create (never drop) tables of `db/missing-objects.sql` that do not exist |
| `idq.clearable-tables-file` | `classpath:db/clearable-tables.txt` | Whitelist of tables a mapping may empty |
| `idq.report.enabled` | `true` | Write the `adhoc_runs_<SOURCE>` audit reports |
| `idq.report.base-dir` | `.` | Directory that holds the `adhoc_runs_<SOURCE>` folders |
| `idq.report.max-rows` | `200` | Rows shown per table in a report (max 1000; totals are always shown) |
| `idq.wallet-dir`, `IDQ_DB_USER`, `IDQ_DB_PASSWORD` | `docs/wallet`, ADMIN | OCI wallet and credentials |

## Notes

* No table is ever dropped. A full-table delete is only allowed for tables in `db/clearable-tables.txt`; other
  targets are rejected by `TargetWriter`. Never run `docs/*_EXPORT_OCT_16.sql`: they contain `DROP TABLE`.
* `db/missing-objects.sql` holds `CREATE TABLE` statements (generated from the workflow XML) for objects missing in
  the OCI schema, e.g. the `V_*` source views, which are created as tables and filled with mock data.
* The `C_S_*` timeline columns (VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION) and the version loops are
  stale and not ported; one row per PKEY is written.
* AddressDoctor is licensed and external: `PassThroughAddressValidator` keeps the source address; plug a real
  validator in by providing another `AddressValidator` bean.
* Deactivation / Reactivation workflows are out of scope.
