/// The IDQ mapplets and rules (name standardization, address validation, phone, e-mail, SSN, Medicaid id, birth date,
/// gender) as plain Java.
///
/// Why it exists: the same rules run inside many mappings of every source. Porting each rule once, against
/// `docs/mappings/000_mapplets.md`, keeps the results identical everywhere. [AddressValidator] stands in for
/// AddressDoctor; [PassThroughAddressValidator] runs all the surrounding expressions without the service.
package com.idq.cli.core.rules;
