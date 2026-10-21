/// Runtime switches read from `application.properties`, as typed records.
///
/// Why it exists: one place decides which engine runs a workflow (Java or Informatica), whether mock data is
/// generated, and where audit reports go. Everything
/// else receives [EtlSettings] / [ReportSettings] instead of reading properties itself.
package com.idq.cli.config;
