/// One package per source system (TRS, ECI, FSS, TTF, WIC), each holding that source's tables and mappings.
///
/// Why it exists: the mappings of a source read its own staging tables and load its own `C_S_<SRC>_*` tables, so
/// they are kept together by source rather than by sub-domain. Every source has the same layout:
///
/// * `etldb.models` / `etldb.repo` - the tables and their Spring Data JDBC repositories
/// * `etldb.svc` - reserved for services that combine several repositories into one business function
/// * `etlmap.svc` - one plain service per IDQ mapping, plus `<Src>Mappings` that registers them
package com.idq.cli.source;
