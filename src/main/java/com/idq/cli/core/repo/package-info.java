/// Building blocks for the Spring Data JDBC repositories of the `source.<src>.etldb.repo` packages.
///
/// Why it exists: the staging tables have assigned keys (`PKEY_SRC_OBJECT`, `SRC_KEY`, ...), so Spring Data's `save`
/// would issue an `UPDATE` instead of an `INSERT`. [InsertRepository] adds a plain `insertAll`, and
/// [TargetTableRepository] exposes only what a target load needs (`deleteAll`), so a repository cannot be misused.
///
/// Spring Data wires a fragment only when a repository extends it directly, so every repository lists
/// [InsertRepository] itself.
package com.idq.cli.core.repo;
