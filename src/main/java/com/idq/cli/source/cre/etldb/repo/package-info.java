/// One Spring Data JDBC repository per CRE source or workflow table, each bound to that table's own entity.
///
/// Why it exists: every query lives on the repository of the table it reads (for a multi-table query, the table that
/// drives it), so it is obvious where SQL lives and what it touches. Source repositories only read;
/// the workflow-table repositories also insert.
///
/// The `C_S_CRE_*` repositories are MDM tables: `com.idq.cli.mdmdc.etldb.repo`.
package com.idq.cli.source.cre.etldb.repo;
