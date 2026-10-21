/// Spring Data JDBC records of the TTF tables, and the result rows of the TTF queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [TtfSources] - source tables and views
/// * [TtfTargets] - target tables `C_S_TTF_*` and the other tables the mappings write
/// * [TtfQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
package com.idq.cli.source.ttf.etldb.models;
