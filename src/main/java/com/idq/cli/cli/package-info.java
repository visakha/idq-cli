/// Interactive Spring Shell front end and the actions behind it.
///
/// Why it exists: a developer works on one mapping at a time. The shell "latches" a source system, a target table
/// and a mapping ([LatchState]), then runs, mocks or tests just that. [EtlConsole] holds the actual actions and
/// enforces the latch order, so the shell and the REST API (`api`) cannot drift apart.
package com.idq.cli.cli;
