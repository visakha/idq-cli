/// Identity of the mappings: which source system, which IDQ mapping, which tables it reads and loads.
///
/// Why it exists: the workflow runner, the shell and the audit reports need to list and order mappings without
/// knowing how each one is implemented. [MemberMapping] is that common view and [MappingInfo] the identity of one
/// mapping; [SourceSystem], [Domain] and [SubDomain] are the business vocabulary (only the Member domain is
/// implemented).
package com.idq.cli.domain;
