/// Audit trail of a workflow run: what each mapping read and wrote, published as events and written as Markdown.
///
/// Why it exists: a Java run has to be checked against the IDQ run. [EtlAudit] captures the source tables, the
/// `IdqMapInitQuery` rows and the loaded target rows as [EtlEvent]s; [AdhocRunReporter] turns them into one report
/// per target table under `adhoc_runs_<SOURCE>/`, with the mock data as replayable SQL next to it. Capturing never
/// fails a run.
package com.idq.cli.core.audit;
