package com.idq.cli.config;

import java.util.Set;

/// Runtime switches read from `application.properties`.
///
/// | property                         | field                     |
/// |----------------------------------|---------------------------|
/// | `etl_process`                    | [#etlProcess]             |
/// | `mock_infacmd`                   | [#mockInfacmd]            |
/// | `mock_data`                      | [#mockData]               |
/// | `idq.mock.rows-per-table`        | [#mockRowsPerTable]       |
/// | `mock-data-pre-fix`              | [#mockDataPrefix]         |
/// | `idq.bootstrap-missing-objects`  | [#bootstrapMissingObjects]|
/// | `idq.clearable-tables-file`      | [#clearableTables]        |
///
/// `mockDataPrefix` (e.g. `Test_001`) is put in front of every free-text mock value, `Test_001-JaneDoe@gmail.com`;
/// codes, keys and reference data are never prefixed. Empty means no prefix.
///
/// `clearableTables` is the whitelist of tables the ETL may empty before a load; tables are never dropped.
public record EtlSettings(
        EtlProcess etlProcess,
        boolean mockInfacmd,
        boolean mockData,
        int mockRowsPerTable,
        String mockDataPrefix,
        boolean bootstrapMissingObjects,
        Set<String> clearableTables,
        Infacmd infacmd) {

    public record Infacmd(String script, String domain, String service, String application) {}

    public boolean mayClear(String table) {
        return clearableTables.contains(table.toUpperCase());
    }
}
