/// One Spring Data JDBC repository per MDM `C_S_*` staging table, named after its source and entity
/// (`EciAddressRepository` is `C_S_ECI_PTY_RLE_ADDR`).
///
/// Why it exists: a mapping loads its `C_S_*` tables the IDQ way, empty then insert, so each repository exposes only
/// `deleteAll` (whitelisted tables only, checked by the caller) and `insertAll`, plus `TABLE`, the table name used for
/// the whitelist and the load counts. `TrsManagedAttributeRepository` also deletes one attribute type for mapping 002.
package com.idq.cli.mdmdc.etldb.repo;
