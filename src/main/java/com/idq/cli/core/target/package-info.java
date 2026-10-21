/// What the `C_S_*` target tables have in common, and the generic loader of the sources not yet migrated.
///
/// Why it exists: every `C_S_<SRC>_*` table carries the same MDM audit columns ([MdmAudit]) and one column group per
/// sub-domain ([Columns]), so transformations are written once and reused by all sources through generics.
/// [TargetWriter], [TargetBatch] and [LoadMode] load TRS, FSS, TTF and WIC; ECI loads through its own repositories
/// (`source.eci.etldb.repo`) instead. [DqmAddress] is the address-validation audit written by all address mappings.
package com.idq.cli.core.target;
