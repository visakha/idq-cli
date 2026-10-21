/// Reserved for pure database services of CRE: a service here stitches several `etldb.repo` repositories together to
/// provide one business function (no IDQ transformation logic).
///
/// The per-mapping service (read, transform, load of one IDQ mapping) lives in `source.cre.etlmap.svc`.
package com.idq.cli.source.cre.etldb.svc;
