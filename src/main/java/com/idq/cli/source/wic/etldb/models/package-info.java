/// Spring Data JDBC records of the WIC tables, and the result rows of the WIC queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [WicSources] - source tables and views
/// * the workflow tables the mappings write are in [WicSources] too (`STG_WIC_PTY_INACTIVE_STS` / `_LOG`)
/// * [WicQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
///
/// The `C_S_WIC_*` tables the mappings load are MDM tables: `com.idq.cli.mdmdc.etldb.models.WicTargets`.
package com.idq.cli.source.wic.etldb.models;
