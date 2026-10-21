# Code path: `run-etl` on ECI

This walkthrough follows `run-etl` with the default settings (`etl_process=JAVA`, `mock_data=true`). The example
mapping is **015 `m_Tgt_C_S_ECI_Pty_Addr`** (`EciAddress`). It shows every stage: mock fill, an init query that returns
typed records, a lookup, reference codes, validation, exception routing and two target tables.

Paths are relative to `src/main/java/com/idq/cli/`.

---

## 0. Entry: shell command → console → runner

```
IdqShellCommands.runEtl()          cli/IdqShellCommands.java:132
  └─ EtlConsole.runEtl()           cli/EtlConsole.java:168
       ├─ sampleData.fillMockAll(names of every ECI mapping)   ← step 1
       └─ runner.run(source)                                   ← steps 2–5
```

`EtlConsole.runEtl` gets the latched `SourceSystem` (ECI). It asks `MappingCatalog.of(ECI)` for that source's mappings
in workflow order: 013 validation, 014 party, then 015–018 (`workflow/MappingCatalog.java:46`). It sends their names to
the mock filler, then hands the source to `WorkflowRunner`. The REST endpoint `POST /api/etl/run`
(`api/EtlController.java:143`) calls the same `console.runEtl()`.

---

## 1. Mock data generation and injection

### 1a. Finding the generators by reflection (`mock/SampleData.java:56`)

```java
var functions = mappings.stream().map(mapping -> MOCK_PREFIX + mapping).toList();
// "fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Addr", ...
var methods = functions.stream().map(function -> find(function).orElseThrow(...)).toList();
```

- `find()` (line 86) searches the public no-argument methods of the four generator beans: `TrsMockData`,
  `EciMockData`, `ViewMockData` and `RealSampleData`.
- The match is by naming convention, so every mapping must have a `fill_sample_mock_data_<mappingName>` method. If one
  is missing, the whole run fails before any ETL starts.
- Before invoking the generators, it does two things:
  1. **`DatabaseBootstrap.createMissingObjects()`** (`workflow/DatabaseBootstrap.java:31`). This reads
     `resources/db/missing-objects.sql` and runs each `CREATE TABLE` whose table is not yet in `USER_TABLES`. Any
     statement that isn't a `CREATE TABLE` throws. This is how `V_ECI_ETL_SRC_FAMILY_ADDRESS` exists as a real
     **table** in OCI (`missing-objects.sql:192`), so mock rows can be inserted into a "view".
  2. **`ReferenceMockData.seed()`** (`mock/ReferenceMockData.java:39`). This seeds the exception catalog, code values,
     master codes, area codes, junk names and street types. Every seeded row carries `CREATED_BY='IDQ_CLI_MOCK'`, so
     it can be deleted with `deleteMarked` and re-seeded on each run.
- Each generator call is wrapped in `recorded(group, ...)`. That calls `MockTables.record(...)` and publishes a
  `MockDataGenerated` event, which the audit reports use (more in 1d).

### 1b. The ECI generator (`mock/EciMockData.java`)

For 015, `fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Addr()` is at `EciMockData.java:101`:

```java
tables.deleteRange("V_ECI_ETL_SRC_FAMILY_ADDRESS", "ID", ID, ID + 999_999);   // 1. clear the mock id range only
for (var id : ids()) {                                                      // 9100000001 .. 9100000020
    tables.insert(entity(EtlSrcFamilyAddress.class)                          // 2. typed builder
        .with(EtlSrcFamilyAddress::sourceTable, i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD")
        .with(EtlSrcFamilyAddress::addressCd, BigDecimal.valueOf(i % 6 == 0 ? 9 : 1))  // deliberately bad code
        .with(EtlSrcFamilyAddress::address1, tables.text(faker.address().streetAddress()))
        ...);
}
```

- **Ids**: `ID = 9_100_000_000L` plus 1 to `idq.mock.rows-per-table` (default 20). Deletes only touch this range, so
  real data is never removed.
- **Datafaker** uses a fixed seed, `new Faker(new Random(7))`, so the data is the same on every run.
- **Edge cases are built in**: every 6th row gets the unknown address code 9, every 3rd row has a line 2, and rows
  alternate between `ECI_FAMILY` and `ECI_CHILD`. These are what drive the exception and lookup branches later.
- **`tables.text(...)`** adds the `mock-data-pre-fix` (for example `Test_001-...`) to free text only. Codes and keys
  never get the prefix.

### 1c. `EntityBuilder`: typed construction without column strings (`core/EntityBuilder.java`)

The source entity is a Spring Data JDBC record (`source/eci/EciSources.java:63`):

```java
@Table("V_ECI_ETL_SRC_FAMILY_ADDRESS")
public record EtlSrcFamilyAddress(String sourceTable, BigDecimal id, @Id BigDecimal idFamilyAddress, ...)
```

`entity(Class)` starts an array of `null`s, one per record component. `.with(ChildDelta::firstName, v)` finds the slot by
name. It gets the name from the method reference: `Component` extends `Serializable`, so the code calls
`writeReplace()` to get a `SerializedLambda` and reads `getImplMethodName()` (line 89), cached per lambda class.
`build()` then calls the canonical constructor by reflection. You get compile-time type checking of values and no
column-name strings.

### 1d. The actual INSERT (`mock/MockTables.java:76`)

```java
public <R extends Record> R insert(R row) {
    var fitted = fitted(row);                 // trims prefixed text to the column's DATA_LENGTH (from USER_TAB_COLUMNS)
    if (recorder.get() != null) statements.add(insertSql(fitted));   // replayable SQL for the audit report
    return aggregates.insert(fitted);         // Spring Data JDBC JdbcAggregateTemplate → INSERT
}
```

- `aggregates.insert` builds the column list from the `@Table` and `@Column` metadata. The default naming strategy
  turns camelCase into snake_case, so `idFamilyAddress` becomes `ID_FAMILY_ADDRESS`.
- `insertSql` walks the same persistent-entity metadata, including embedded groups, and renders an
  `INSERT ... VALUES (literals);` string. A thread-local recorder collects these strings, so the generated data shows up
  in the `adhoc_runs_ECI` reports as SQL you can paste.
- There is no surrounding transaction here. Each insert auto-commits.

**One thing to know:** `childrenAndFamilies()` is called by the generators for 013, 014, 016 and 018. On ECI it runs 4
times per `run-etl`. Each call deletes the range and re-inserts, so the row counts stay correct. But the Faker sequence
moves on each time, so the names left in the tables come from the last call.

---

## 2. Workflow set-up (`workflow/WorkflowRunner.java:69`)

```java
var reference = referenceLoader.load();                 // one ReferenceSnapshot for the whole workflow
var trail = audit.start(source, EtlProcess.JAVA, runStart);
mappings.stream().map(m -> runOne(m, new EtlContext(m.info(), runStart, reference), trail))
```

- **`ReferenceLoader.load()`** (`core/reference/ReferenceLoader.java`) runs the `ReferenceQueries` named queries once.
  They read the lookup code values, master code view, exception codes, area codes, junk names and street types. The
  results go into an in-memory `ReferenceSnapshot`, the equivalent of IDQ's lookup caches.
- **`EtlContext`** (`core/EtlContext.java`) holds the `MappingInfo`, a fixed `runStart` and the snapshot. `runStart`
  stands in for `$sys.MappingRunStartTime`, `SYSDATE` and `SYSTIMESTAMP`, so output is reproducible.
- Each mapping runs inside `runOne` (line 100). A failure is caught, logged and recorded as `MappingResult.failed`, and
  the workflow carries on with the next mapping.

`runOne` is a fluent pipeline (`core/MappingFlow.java`):

```java
MappingFlow.of(mapping).read().peek(rows -> trail.initQuery(mapping, rows)).transform(ctx).writeWith(writer);
```

Each step returns a new immutable record: `Reader` → `Transformer` → `Writer` → `MappingResult`.

---

## 3. The `IdqMapInitQuery` and typed results

### 3a. Wiring

`EciAddress` extends `SourceMapping` (`domain/SourceMapping.java`). Its constructor binds two suppliers:

```java
super(INFO, queries::fetchFamilyAddresses,                                   // init query
      () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));  // mapping lookup
```

`MappingFlow.Reader.read()` calls `mapping.fetchIdqMapInitQueryResults()`, which runs `initQuery.get()`, and then
`fetchLookups()`.

### 3b. The query (`source/eci/EciQueries.java`)

`EciQueries` is a Spring Data JDBC **`Repository` interface**. There is no implementation class.
`@EnableJdbcRepositories(considerNestedRepositories = true)` in `CliApplication.java:10` makes Spring generate a proxy
at startup.

```java
record FamilyAddress(String sourceTable, Long id, Long idFamilyAddress, String address1, String address2,
        String addressCd, String cityName, String countyName, String stateAbbrev, String zipCode, String zipSfx,
        LocalDateTime lastUpdateDate) {}

@Query("""
        SELECT source_table, id, id_family_address, address1, address2, address_cd, city_name, county_name,
               state_abbrev, zip_code, zip_sfx, last_update_date
        FROM v_eci_etl_src_family_address
        """)
List<FamilyAddress> fetchFamilyAddresses();
```

How the rows become typed records:

- The SQL is the mapping's first SQL, ported from the IDQ mapping doc (`docs/mappings/015_...md`).
- The return type `FamilyAddress` is a **plain record, not an entity**. Spring Data JDBC's converter maps each
  result-set column to a constructor parameter by name, using snake_case ↔ camelCase (`address_cd` → `addressCd`).
- It also converts types: Oracle `NUMBER` becomes `Long` or `String`. Note that `addressCd` is a `BigDecimal` in the
  source entity but a `String` here, because the transformation compares it to code-value strings.
- The read model (`EciQueries.FamilyAddress`) is deliberately separate from the write model used for mocks
  (`EciSources.EtlSrcFamilyAddress`).

### 3c. Audit peek

`.peek(rows -> trail.initQuery(mapping, rows))` passes the typed rows to `EtlAudit` before the transform. That is how
the `IdqMapInitQuery` rows end up in the Markdown reports. Before that, `trail.sources(info)` snapshots the source
tables listed in `MappingInfo.sourceEntities`.

---

## 4. The core ETL logic (`source/eci/EciAddress.java:54`)

`transform(rows, lookups, ctx)` is a **pure function**. It makes no DB calls, which is why it can be unit tested
(`EciPkeyTest`) without Oracle. The `MemberMapping` contract says so explicitly (`domain/MemberMapping.java`).

**Step 4.1: filter out inactive parties** (IDQ `Flt_Remove_Inactive`)

```java
.filter(a -> inactive.isActive(EciPartyValidation.partyKey(a.sourceTable(), a.id())))
```

The lookup is a `Map` built from `STG_ECI_PTY_INACTIVE_STS`. A row is dropped if its party key has a deactivation
status (`core/InactiveStatus.java:29`).

**Step 4.2: build a `Candidate` per row, with keys formed IDQ-style**

- `ctx.reference().masterCode("ADDR_TP", "ECI", a.addressCd())` translates the source code to the MDM address type.
  For code `9` it returns empty, so the type is `null`. That null is what produces the exception later.
- `pkey(a, type)` (line 47) builds `PKEY_SRC_OBJECT`:
  `<partyKey>|Member|<type>|<id_family_address LPAD 10>|<LINE1>|<LINE2>|<CITY>|<STATE>|<zip>|<zip4>`.
  It uses the `Infa` helpers (`pipe`, `lpad`, `trim`, `upper`), which copy Informatica expression semantics, including
  null handling.
- `Columns.SourceAddress` holds the address exactly as the source sent it.

**Step 4.3: the shared address pattern** (`core/AddressPatterns.java:69`)

`AddressPatterns.route(candidates, validator, ctx, EciTargets.Address::new)` is generic code shared by TRS, ECI, FSS
and WIC. For each candidate:

1. `validator.validate(...)` stands in for AddressDoctor. The injected bean is `PassThroughAddressValidator`.
2. It always adds a `DqmAddress` audit row.
3. `AddressRules.score(type, mailability, matchCode)` decides the outcome:
   - `EXCEPTION`: it builds a `BadRecord` (`Invalid_Address`) through `ctx.badRecord()...build()` and moves to the
     next candidate.
   - Otherwise it builds the target row:
     ```java
     var audit = MdmAudit.srcRowid(c.pkey()).periodStart(...).lastUpdated(ctx.runStart())
             .created(...).by(null, ctx.mappingName()).hubState(1).sourceUpdated(...);
     factory.create(c.pkey(), audit, new Columns.Address(ptyRleFk, type, "Primary", "Member", "Member Addr", locIdn,
             validated(av, ...), src, effBegin, null));
     ```

`factory` is `EciTargets.Address::new`, a `RowFactory`. This is how a generic pattern produces a source-specific typed
entity.

**Step 4.4: assemble the `MappingOutput`** (in load order)

```java
return MappingOutput.empty()
        .load(TargetBatch.append(DqmAddress.class, routed.dqm()))
        .load(TargetBatch.replaceAll(EciTargets.Address.class,
                Rows.lastPerKey(routed.addresses(), EciTargets.Address::pkeySrcObject)))   // IDQ aggregator on PKEY
        .reject(routed.exceptions());
```

`MappingOutput` (`core/MappingOutput.java`) holds the batches plus the bad records. Each `TargetBatch` carries the
entity class, the rows and a `LoadMode`.

---

## 5. Writing the typed entity into `C_S_ECI_PTY_RLE_ADDR`

### 5a. The target entity (`source/eci/EciTargets.java`)

```java
@Table("C_S_ECI_PTY_RLE_ADDR")
public record Address(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
        @Embedded.Empty Columns.Address columns) implements StagingRow<Columns.Address> {}
```

- **`@Embedded.Empty`** flattens the nested records into columns of the same table. Columns are:
  - `MdmAudit`: `PERIOD_START_DATE`, `SRC_ROWID`, `HUB_STATE_IND`, ...
  - `Columns.Address`: `PTY_RLE_FK`, `ADDR_TP`, ...
  - Nested inside it, `ValidatedAddress` (`ADDR_LN_1`, `CITY`, ...) and `SourceAddress` (`SRC_ADDR_LN_1`, ...).
- **`@Column`** overrides cover the names the naming strategy can't produce, such as `ADDR_LN_1`.
- So one `C_S_*` row is a 3-level typed object graph. Each source system declares only a tiny record; the column groups
  are shared (`core/target/Columns.java`).

### 5b. `TargetWriter.write` (`core/target/TargetWriter.java:31`)

```java
tx.executeWithoutResult(_ -> output.batches().forEach(batch -> counts.merge(batch.table(), apply(batch), Integer::sum)));
```

- **All batches of a mapping run in one transaction.** If one fails, the mapping writes nothing, and `runOne` records
  it as FAILED.
- `output.batches()` returns the target batches plus a final `TargetBatch.append(BadRecord.class, badRecords)`. That is
  how exceptions reach `EXC_STG_BAD_REC_MEMB`.
- `apply` switches on the sealed `LoadMode`:

| Batch | Mode | SQL |
|---|---|---|
| `DQM_ADDRESS` | `Append` | inserts only |
| `C_S_ECI_PTY_RLE_ADDR` | `ReplaceAll` | `clear()` checks the `db/clearable-tables.txt` whitelist (the table is on line 18; anything not listed throws), then `DELETE FROM C_S_ECI_PTY_RLE_ADDR`, then inserts. This is IDQ's "truncate target". |
| `EXC_STG_BAD_REC_MEMB` | `Append` | inserts only |

- Finally, `aggregates.insertAll(batch.rows())` hands the records to Spring Data JDBC. It flattens the embedded groups
  into one `INSERT INTO C_S_ECI_PTY_RLE_ADDR (PKEY_SRC_OBJECT, PERIOD_START_DATE, ..., ADDR_LN_1, ..., SRC_ADDR_LN_1, ...)`
  per row, binding the values from the record accessors.

### 5c. Wrap-up

- `Writer.writeWith` returns a `MappingResult` with rows read, a written count per table and the exception count.
- `trail.written(...)` and `trail.finished(...)` feed the audit reports.
- The `summary()` lines, plus the mock line from step 1 and the `Audit reports: <dir>` line, are what the shell prints.

---

## Data flow for one mock row (id 9100000006)

```
EciMockData  → INSERT V_ECI_ETL_SRC_FAMILY_ADDRESS (ADDRESS_CD=9, SOURCE_TABLE='ECI_FAMILY', ...)
EciQueries.fetchFamilyAddresses → FamilyAddress(sourceTable="ECI_FAMILY", id=9100000006, addressCd="9", ...)
EciAddress.transform → masterCode(ADDR_TP, ECI, "9") = empty → type null
AddressPatterns.route → DqmAddress row (always) + score = EXCEPTION → BadRecord "Invalid_Address"
TargetWriter → INSERT DQM_ADDRESS; nothing in C_S_ECI_PTY_RLE_ADDR; INSERT EXC_STG_BAD_REC_MEMB
```

The other rows, with `ADDRESS_CD=1`, take the success branch and end up as `EciTargets.Address` records in
`C_S_ECI_PTY_RLE_ADDR`.

## With `etl_process=IDQ`

Steps 2–5 are replaced by `runIdq` (`WorkflowRunner.java:83`). The init queries still run, but only for the audit.
Informatica does the transform through the infacmd script, and the audit snapshots the target tables afterwards.

## With `etl_process=ORA_SP`

Steps 2–5 are replaced by `runOraSp` (`workflow/WorkflowRunner.java`). `OraSpRunner.procedures(ECI)` reads the `EXEC`
lines of `idq-to-oracle/wf_ECI_Stage_Load/run_wf_ECI_Stage_Load.sql`, which gives nine procedures in taskflow order.
For each procedure that matches a catalog mapping (`sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr` → 015), the audit captures
the sources and the init query, `OraSpRunner.call` runs `BEGIN sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr; END;`, and the
audit snapshots the target tables. The three reactivation procedures have no Java mapping, so they are called
without an audit. The first `FAILED` call stops the run, and the remaining procedures are `SKIPPED`. With
`mock_ora_sp=true` (the default) no procedure is called.
