package com.idq.cli.config;

import java.nio.file.Path;

/// Runtime switches read from `application.properties`.
///
/// | property                         | field                     |
/// |----------------------------------|---------------------------|
/// | `etl_process`                    | [#etlProcess]             |
/// | `mock_infacmd`                   | [#mockInfacmd]            |
/// | `mock_ora_sp`                    | [#mockOraSp]              |
/// | `mock_data`                      | [#mockData]               |
/// | `idq.mock.rows-per-table`        | [#mockRowsPerTable]       |
/// | `mock-data-pre-fix`              | [#mockDataPrefix]         |
/// | `idq.bootstrap-missing-objects`  | [#bootstrapMissingObjects]|
/// | `idq.ora-sp.dir`                 | [#oraSpDir]               |
///
/// `mockDataPrefix` (e.g. `Test_001`) is put in front of every free-text mock value, `Test_001-JaneDoe@gmail.com`;
/// codes, keys and reference data are never prefixed. Empty means no prefix.
///
/// `oraSpDir` is the `idq-to-oracle` folder that holds `<workflow>/run_<workflow>.sql` (`etl_process=ORA_SP`).
///
/// Nothing in this application deletes, truncates or drops: loads only insert.
public record EtlSettings(
        EtlProcess etlProcess,
        boolean mockInfacmd,
        boolean mockOraSp,
        boolean mockData,
        int mockRowsPerTable,
        String mockDataPrefix,
        boolean bootstrapMissingObjects,
        Infacmd infacmd,
        Path oraSpDir) {

    public record Infacmd(String script, String domain, String service, String application) {}
}
