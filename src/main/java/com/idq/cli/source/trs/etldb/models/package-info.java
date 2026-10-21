/// Spring Data JDBC records of the TRS tables, and the result rows of the TRS queries.
///
/// Why it exists: every table the mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [TrsSources] - source tables and views
/// * the workflow tables the mappings write are in [TrsSources] too (`STG_TRS_VALID_MEMBERS`, `STG_TRS_D_UNQ_ADDR`)
/// * [TrsQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
///
/// The `C_S_TRS_*` tables the mappings load are MDM tables: `com.idq.cli.mdmdc.etldb.models.TrsTargets`.
package com.idq.cli.source.trs.etldb.models;
