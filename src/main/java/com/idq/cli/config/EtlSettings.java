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
/// | `idq.bootstrap-missing-objects`  | [#bootstrapMissingObjects]|
/// | `idq.clearable-tables-file`      | [#clearableTables]        |
///
/// `clearableTables` is the whitelist of tables the ETL may empty before a load; tables are never dropped.
public record EtlSettings(
        EtlProcess etlProcess,
        boolean mockInfacmd,
        boolean mockData,
        int mockRowsPerTable,
        boolean bootstrapMissingObjects,
        Set<String> clearableTables,
        Infacmd infacmd) {

    public record Infacmd(String script, String domain, String service, String application) {}

    public boolean mayClear(String table) {
        return clearableTables.contains(table.toUpperCase());
    }
}
