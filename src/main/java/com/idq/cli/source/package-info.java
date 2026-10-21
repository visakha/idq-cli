/// One package per source system (TRS, ECI, FSS, TTF, WIC), each holding that source's tables and mappings.
///
/// Why it exists: the mappings of a source read its own staging tables and load its own `C_S_<SRC>_*` tables, so
/// they are kept together by source rather than by sub-domain. ECI uses the `etldb` / `etlmap` layout; the other
/// sources still use one flat package per source.
package com.idq.cli.source;
