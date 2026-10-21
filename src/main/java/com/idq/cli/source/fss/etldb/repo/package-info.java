/// One Spring Data JDBC repository per FSS table, each bound to that table's own entity.
///
/// Why it exists: every query lives on the repository of the table it reads (for a multi-table query, the table that
/// drives it), so it is obvious where SQL lives and what it touches. Source repositories only read; target
/// repositories (`C_S_FSS_*`) expose only `deleteAll` and `insertAll`.
package com.idq.cli.source.fss.etldb.repo;
