# Other Items to Dig Later


  EntityBuilder was not redundant after the mdmdc move alone. It built mock rows for source and reference tables, which
  mdmdc doesn't touch. These changes made it redundant:
  - Mock data: the 33 records the mock data builds got a plain builder(), the same style FamilyDelta and SnChild already
    had. All chains now read ChildDelta.builder().idChild(id).firstName(...).build().
  - MockTables: it copies a row with shortened prefixed text through Spring Data's InstantiationAwarePropertyAccessor,
    instead of EntityBuilder.from(row).map(...). It now reads table names from Spring Data's mapping metadata. No unit
    test exercises this path in MockTables itself. I checked the copy with a throwaway test on a real record, then
    deleted the test.
  - SourceEntitiesIT: it builds its sample rows with Spring Data's entity instantiator. It compiles, but like the other
    Oracle tests it hasn't been run.
  - Deleted: EntityBuilder.java and EntityBuilderTest.java.

  Reflection still left in main code. None of it is the homemade ORM, but you asked me to double-check:
  - MarkdownTable (audit reports) reads record components and @Column to print rows. It could use Spring Data's mapping
    metadata, as MockTables now does.
  - TableEntities (audit reports) scans the classpath to map a table name to its entity.
  - SampleData finds fill_sample_mock_data_<mapping> methods by name. This is command dispatch, not ORM.
  - TargetBatch.table() and MappingInfo.table() read the @Table annotation directly.
  - Tests only: Fixtures.stub uses a JDK proxy for repository stubs, and SourceEntitiesIT lists the entity holders'
    nested records.

  - MarkdownTable and TableEntities still use reflection. I can move them onto
  Spring Data's mapping metadata on this branch if you want. The PR isn't merged.

  - All 40 tests pass, confirming the Spring-metadata rendering matches the old output, but TableEntities isn't covered.
  I'll write a throwaway Spring Boot test to verify the mapping context includes all @Table entities at startup.

  - The mapping context knows all 89 @Table entities declared in the code
  - MarkdownTable and TableEntities now use Spring Data's mapping metadata instead of their own reflection. I committed
  this as 17daa5b on mdmdc-staging-tables and pushed it, so PR #9 now carries it alongside the mdmdc commit.

  - MarkdownTable (audit-report tables) now reads column names and values from Spring Data's mapping context. The column
    names are the ones Spring Data JDBC itself reads and writes. The record-component and ReflectionUtils code is gone.
    Embedded groups (MdmAudit, Columns.*) and composite keys are still flattened, and AdhocRunReporterTest passes with
    the same headers and values as before.
  - TableEntities builds its table → entity map from the @Table entities Spring Boot already registers at startup,
    instead of scanning the classpath itself. A throwaway startup test found all 89 declared @Table entities, and every
    table I probed resolved: C_S_*, STG_*, C_B_*, LOOKUP_*, EXC_*, DQM_*, V_*. I deleted that test afterwards.
  - AdhocRunReporter now receives the mapping context; its test passes a JdbcMappingContext.

  All 40 unit tests pass on a clean build. The Oracle integration tests are still not run.

  What remains in main code is the SampleData dispatch, which finds fill_sample_mock_data_<mapping> methods by name, and
  the plain @Table reads in TargetBatch.table() and MappingInfo.table(). Neither is ORM-style.

  