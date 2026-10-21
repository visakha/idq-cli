/// Spring Data JDBC records of the FSS tables, and the result rows of the FSS queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [FssSources] - source tables and views
/// * the workflow tables the mappings write are in [FssSources] too (`STG_FSS_PTY_INACTIVE_STS` / `_LOG`)
/// * [FssQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
///
/// The `C_S_FSS_*` tables the mappings load are MDM tables: `com.idq.cli.mdmdc.etldb.models.FssTargets`.
package com.idq.cli.source.fss.etldb.models;
