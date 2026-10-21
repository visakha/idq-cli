/// Spring Data JDBC records of the TTF tables, and the result rows of the TTF queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [TtfSources] - source tables and views
/// * the workflow tables the mappings write are in [TtfSources] too (`STG_TTF_PTY_INACTIVE_STS` / `_LOG`)
/// * [TtfQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
///
/// The `C_S_TTF_*` tables the mappings load are MDM tables: `com.idq.cli.mdmdc.etldb.models.TtfTargets`.
package com.idq.cli.source.ttf.etldb.models;
