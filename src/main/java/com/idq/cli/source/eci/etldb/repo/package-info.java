/// One Spring Data JDBC repository per ECI source or workflow table, each bound to that table's own entity.
///
/// Why it exists: every query lives on the repository of the table it reads (`EciFamilyDeltaRepository` holds the
/// query over `STG_ECI_D_FAMILY`), so it is obvious where SQL lives and what it touches. Source repositories only read;
/// the workflow-table repositories also insert; the inactive-status repository also deletes reactivated parties by key.
///
/// The `C_S_ECI_*` repositories are MDM tables: `com.idq.cli.mdmdc.etldb.repo`.
package com.idq.cli.source.eci.etldb.repo;
