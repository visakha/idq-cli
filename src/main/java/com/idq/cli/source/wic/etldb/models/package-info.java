/// Spring Data JDBC records of the WIC tables, and the result rows of the WIC queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [WicSources] - source tables and views
/// * [WicTargets] - target tables `C_S_WIC_*` and the other tables the mappings write
/// * [WicQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
package com.idq.cli.source.wic.etldb.models;
