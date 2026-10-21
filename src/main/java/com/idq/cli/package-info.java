/// IDQ replacement ETL: a Java re-implementation of the Informatica IDQ Member workflows, driven from an interactive
/// shell and a REST API.
///
/// Why it exists: the IDQ mappings that load the MDM staging tables (`C_S_*`) are being moved off Informatica. Each
/// mapping is ported so its output can be compared with the IDQ run on the same source rows, table by table.
///
/// Layout: `cli` / `api` are the two front ends, `workflow` runs a source's mappings in IDQ order, `source.<src>`
/// holds the source-specific tables and mappings, `core` the logic shared by all sources, `mock` the test data.
/// See `README.md`.
package com.idq.cli;
