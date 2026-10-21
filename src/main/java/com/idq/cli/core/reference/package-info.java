/// Shared lookup tables (code translations, exception catalog, area codes, junk names, street types) and the MDM base
/// tables some mappings look up.
///
/// Why it exists: IDQ caches its lookups; here [ReferenceLoader] reads them once per workflow run into an in-memory
/// [ReferenceSnapshot], so transformations look codes up without touching the database and unit tests can build the
/// snapshot by hand.
package com.idq.cli.core.reference;
