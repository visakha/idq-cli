/// Spring Data JDBC records of the ECI tables, and the result rows of the ECI queries.
///
/// Why it exists: every table the ECI mappings read or load has one record, column for column, so data is typed end
/// to end and the audit reports can print any table.
///
/// * [EciSources] - source tables and views (`STG_ECI_D_*`, `STG_ECI_SN_*`, `V_ECI_ETL_*`); the `_D_` (delta)
///   tables are named `<Name>Delta`
/// * the workflow tables the mappings write are in [EciSources] too (`STG_ECI_PTY_INACTIVE_STS` / `_LOG`)
/// * [EciQueryRows] - rows returned by the `IdqMapInitQuery`s and lookups; projections, not tables
///
/// The `C_S_ECI_*` tables the mappings load are MDM tables: `com.idq.cli.mdmdc.etldb.models.EciTargets`.
package com.idq.cli.source.eci.etldb.models;
