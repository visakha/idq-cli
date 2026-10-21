/// One plain `@Service` per TRS IDQ mapping (001 to 012), named after it.
///
/// Why it exists: each service reads like the mapping it ports, as steps a reader can follow top to bottom:
///
/// 1. `fetch<Rows>()` - the `IdqMapInitQuery`, through `etldb.repo`
/// 2. `fetch<Lookups>()` - the mapping's lookups, when it has any
/// 3. `transform(...)` - the IDQ logic, a pure function unit tested without a database (`TrsPkeyTest`)
/// 4. `load(...)` - one transaction of named repository steps such as `replaceParties`
///
/// The services implement no interface; [TrsMappings] hands their methods to the workflow runner.
package com.idq.cli.source.trs.etlmap.svc;
