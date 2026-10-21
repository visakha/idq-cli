/// One plain `@Service` per ECI IDQ mapping (013 to 018), named after it: `EciAddressService` is
/// `m_Tgt_C_S_ECI_Pty_Addr`.
///
/// Why it exists: each service reads like the mapping it ports, as four steps a reader can follow top to bottom:
///
/// 1. `fetch<Rows>()` - the `IdqMapInitQuery`, through `etldb.repo`
/// 2. `fetch<Lookups>()` - e.g. `fetchDeactivatedParties()`, the parties mapping 013 deactivated
/// 3. `transform(...)` - the IDQ logic, a pure function unit tested without a database (`EciPkeyTest`)
/// 4. `load(...)` - one transaction of named repository steps such as `replaceAddresses`
///
/// The services implement no interface; [EciMappings] hands their methods to the workflow runner.
package com.idq.cli.source.eci.etlmap.svc;
