# Tester Pipeline Sequence Diagrams (v5.5.0)

Mermaid `sequenceDiagram` views of the daily tester flow. The
diagrams match the endpoint and safety-gate behaviour in
`PIPELINE_USER_GUIDE.md` exactly: the whitelist refusal in (C),
the failure-stops-later-workflows rule in (D), and the
record-by-record merge in (F) are all drawn, not implied.

## 1. Overall daily flow (steps A to G)

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant ProdOracle as Oracle Production
    participant ProdSQLite as Prod_SQLite
    participant DevOracle as Dev Oracle
    participant SnowDev as Snowflake Dev
    participant DevSQLite as Dev_SQLite
    participant Results as Compare_Results_SQLite
    participant UI as Streamlit App

    Note over Tester,API: Step A - Production ETL completed by 8 AM
    Tester->>API: GET readiness
    API->>ProdOracle: Check input and output tables exist
    ProdOracle-->>API: Table existence and row counts
    API-->>Tester: Ready or not ready

    Note over Tester,ProdSQLite: Step B - Prod to Prod_SQLite
    Tester->>API: POST prod-to-sqlite
    API->>ProdOracle: Copy input and output tables
    ProdOracle-->>API: Rows
    API->>ProdSQLite: Write prod file
    API-->>Tester: Prod_SQLite filename

    Note over Tester,DevOracle: Step C - Prod_SQLite to Dev Oracle
    Tester->>API: POST sqlite-to-dev
    API->>DevOracle: Truncate whitelisted tables and load
    DevOracle-->>API: Loaded row counts
    API-->>Tester: Loaded per table

    Note over Tester,SnowDev: Step D - Run Snowflake ETL in Dev
    Tester->>API: POST run-snowflake-etl
    API->>SnowDev: CALL stage-load runners in order
    SnowDev-->>API: Runner summaries
    API-->>Tester: Workflow results

    Note over Tester,DevSQLite: Step E - Snowflake Dev to Dev_SQLite
    Tester->>API: POST snowflake-to-sqlite
    API->>SnowDev: Copy output tables
    SnowDev-->>API: Rows
    API->>DevSQLite: Write dev file
    API-->>Tester: Dev_SQLite filename

    Note over Tester,Results: Step F - Compare
    Tester->>API: POST compare
    API->>ProdSQLite: Stream output tables in PK order
    API->>DevSQLite: Stream output tables in PK order
    API->>Results: Write summaries and diff rows
    API-->>Tester: Verdict and results filename

    Note over Tester,UI: Step G - Manual verification
    Tester->>UI: Open results file
    UI->>Results: Read summaries and diff rows
    Results-->>UI: Tables and diffs
    UI-->>Tester: Tables, diffs, record detail
```

## 2. Step A - Readiness check

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant ProdOracle as Oracle Production

    Tester->>API: GET readiness for source TRS
    API->>ProdOracle: For each registry table, probe existence
    ProdOracle-->>API: Exists or missing, with row counts
    alt Every table exists
        API-->>Tester: Ready true with row counts
    else Some tables missing
        API-->>Tester: Ready false naming missing tables
    end
    Note over Tester,API: Readiness proves existence, not freshness
```

## 3. Step B - Prod Oracle to Prod_SQLite

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant ProdOracle as Oracle Production
    participant ProdSQLite as Prod_SQLite

    Tester->>API: POST prod-to-sqlite with source and tables
    API->>API: Resolve tables from the registry
    alt Unknown table name
        API-->>Tester: 400 naming the unknown table
    else Tables resolved
        API->>ProdSQLite: Create fresh prod file
        loop For each table in registry order
            API->>ProdOracle: Stream rows in batches
            ProdOracle-->>API: Row batches
            API->>ProdSQLite: Insert batches
            API->>ProdOracle: Count source rows
            API->>ProdSQLite: Count target rows
        end
        API-->>Tester: Per-table results and Prod_SQLite filename
    end
```

## 4. Step C - Prod_SQLite to Dev Oracle (whitelist-gated)

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant ProdSQLite as Prod_SQLite
    participant DevOracle as Dev Oracle
    participant WL as Whitelist file

    Tester->>API: POST sqlite-to-dev with Prod_SQLite filename
    API->>API: Refuse if Prod and Dev connections are identical
    API->>WL: Load whitelisted table names
    alt Whitelist file missing
        API-->>Tester: 400, nothing truncated
    else Whitelist loaded
        API->>API: Check every requested table is whitelisted
        alt A table is not whitelisted
            API-->>Tester: 400 naming offenders, nothing truncated
        else All tables whitelisted
            loop For each table
                API->>DevOracle: Check table exists in Dev
                alt Table missing in Dev
                    API-->>Tester: Table NOT_FOUND, run PARTIAL
                else Table exists in Dev
                    API->>DevOracle: Truncate table
                    API->>ProdSQLite: Stream rows in batches
                    ProdSQLite-->>API: Row batches
                    API->>DevOracle: Insert batches
                    API->>DevOracle: Count target rows
                end
            end
            API-->>Tester: Per-table loaded results
        end
    end
```

## 5. Step D - Run the Snowflake ETL in Dev

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant SnowDev as Snowflake Dev

    Tester->>API: POST run-snowflake-etl with source and workflows
    API->>API: Resolve workflow keys from the registry allowlist
    alt Unknown workflow key
        API-->>Tester: 400 naming the unknown workflow
    else Workflows resolved
        opt reset_outputs is true
            API->>SnowDev: Truncate Dev output tables
        end
        loop For each workflow in order
            API->>SnowDev: CALL runner procedure
            SnowDev-->>API: Runner summary string
            alt Runner failed
                API-->>Tester: FAILED, later workflows NOT_RUN
            end
        end
        API-->>Tester: Per-workflow results
    end
    Note over Tester,API: Demo mode runs the simulator instead
```

## 6. Step E - Snowflake Dev to Dev_SQLite

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant SnowDev as Snowflake Dev
    participant DevSQLite as Dev_SQLite

    Tester->>API: POST snowflake-to-sqlite with source and tables
    API->>API: Resolve output tables from the registry
    alt Unknown table name
        API-->>Tester: 400 naming the unknown table
    else Tables resolved
        API->>DevSQLite: Create fresh dev file
        loop For each output table
            API->>SnowDev: Stream rows in batches
            SnowDev-->>API: Row batches
            API->>DevSQLite: Insert batches
            API->>SnowDev: Count source rows
            API->>DevSQLite: Count target rows
        end
        API-->>Tester: Per-table results and Dev_SQLite filename
    end
```

## 7. Step F - Compare Prod_SQLite vs Dev_SQLite

```mermaid
sequenceDiagram
    actor Tester
    participant API as Pipeline API
    participant ProdSQLite as Prod_SQLite
    participant DevSQLite as Dev_SQLite
    participant Results as Compare_Results_SQLite

    Tester->>API: POST compare with both filenames
    API->>API: Resolve output tables from the registry
    API->>Results: Create compare_runs, table_summary, row_diffs
    loop For each output table
        API->>ProdSQLite: Stream rows in PK order
        API->>DevSQLite: Stream rows in PK order
        API->>API: Merge rows by PK
        alt Same PK and all columns equal
            API->>API: Count as matched
        else Same PK and a column differs
            API->>Results: Store DIFFERENT with columns and values
        else PK only on one side
            API->>Results: Store ONLY_IN_PROD or ONLY_IN_DEV
        end
        API->>Results: Store table summary with complete counts
    end
    API->>Results: Store run row with verdict
    API-->>Tester: Verdict, summaries, results filename
```

## 8. Step G - Streamlit manual verification

```mermaid
sequenceDiagram
    actor Tester
    participant UI as Streamlit App
    participant Results as Compare_Results_SQLite

    Tester->>UI: Open app and pick a results file
    UI->>Results: Read compare_runs
    Results-->>UI: Run list with verdicts
    Tester->>UI: Pick a run
    UI->>Results: Read table_summary for the run
    Results-->>UI: Per-table counts and statuses
    UI-->>Tester: Summary table and metrics
    Tester->>UI: Pick a table and a diff status
    UI->>Results: Read row_diffs for table and status
    Results-->>UI: Diff rows
    UI-->>Tester: Diff table
    Tester->>UI: Pick one row
    UI-->>Tester: PK with Prod and Dev values side by side
```
