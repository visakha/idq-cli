/// One Spring Data JDBC repository per MDM `C_S_*` staging table, named after its source and entity
/// (`EciAddressRepository` is `C_S_ECI_PTY_RLE_ADDR`).
///
/// Why it exists: a mapping loads its `C_S_*` tables by inserting rows, so each repository exposes only `insertAll`,
/// plus `TABLE`, the table name used for the load counts. No repository deletes, truncates or drops.
package com.idq.cli.mdmdc.etldb.repo;
