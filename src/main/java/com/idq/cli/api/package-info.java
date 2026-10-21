/// REST front end: every shell command is also an HTTP endpoint under `/api/etl`.
///
/// Why it exists: so the ETL can be scripted or called from other systems without the interactive shell.
/// [EtlController] and the shell share one latched context and delegate to the same `cli.EtlConsole`, so both
/// behave identically; [EtlApiClient] is a typed client for it.
package com.idq.cli.api;
