/// Spring Data JDBC records of the CRE tables, and the result rows of the CRE queries.
///
/// Why it exists: every table the mapping reads or loads has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [CreSources] - source tables (the delta, the snapshot and the case maintenance)
/// * the merge table the mapping writes is in [CreSources] too (`CRE_SRC_MRG`)
/// * [CreQueryRows] - rows returned by the `IdqMapInitQuery` and lookups; projections, not tables
///
/// The `C_S_CRE_*` tables the mapping loads are MDM tables: `com.idq.cli.mdmdc.etldb.models.CreTargets`.
package com.idq.cli.source.cre.etldb.models;
