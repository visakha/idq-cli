/// Reserved for pure database services of ECI: a service here stitches several `etldb.repo` repositories together to
/// provide one business function (no IDQ transformation logic).
///
/// The per-mapping services (read, transform, load of one IDQ mapping) live in `source.eci.etlmap.svc`.
package com.idq.cli.source.eci.etldb.svc;
