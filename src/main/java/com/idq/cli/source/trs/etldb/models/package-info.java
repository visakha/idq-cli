/// Spring Data JDBC records of the TRS tables, and the result rows of the TRS queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [TrsSources] - source tables and views
/// * [TrsTargets] - target tables `C_S_TRS_*` and the other tables the mappings write
/// * [TrsQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
package com.idq.cli.source.trs.etldb.models;
