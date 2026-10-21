/// Runs a source system's mappings in IDQ workflow order, with the engine selected by `etl_process`.
///
/// Why it exists: a mapping depends on the ones before it (validation 013 decides who later mappings skip), so
/// mappings are never run in arbitrary order. [MappingCatalog] orders them as the IDQ workflow does,
/// [WorkflowRunner] runs them in Java, starts the Informatica workflow ([IdqCommandRunner]) or calls the Oracle
/// stored procedures ([OraSpRunner]), [EtlCompareRunner] runs ORA_SP and IDQ on the same source data and compares
/// their target tables, and
/// [DatabaseBootstrap] creates missing tables (create only, never drop or alter).
package com.idq.cli.workflow;
