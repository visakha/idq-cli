/// Reserved for pure database services of TRS: a service here stitches several `etldb.repo` repositories together to
/// provide one business function (no IDQ transformation logic).
///
/// The per-mapping services (read, transform, load of one IDQ mapping) live in `source.trs.etlmap.svc`.
package com.idq.cli.source.trs.etldb.svc;
