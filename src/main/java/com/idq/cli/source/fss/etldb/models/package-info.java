/// Spring Data JDBC records of the FSS tables, and the result rows of the FSS queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [FssSources] - source tables and views
/// * [FssTargets] - target tables `C_S_FSS_*` and the other tables the mappings write
/// * [FssQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
package com.idq.cli.source.fss.etldb.models;
