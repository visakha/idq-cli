/// What the `C_S_*` target tables have in common, and how a mapping describes what it loads.
///
/// Why it exists: every `C_S_<SRC>_*` table carries the same MDM audit columns ([MdmAudit]) and one column group per
/// sub-domain ([Columns]), so transformations are written once and reused by all sources through generics.
/// A transformation describes what it loads as [TargetBatch]es with a [LoadMode] (replace all, replace where,
/// append, delete by key); the mapping service then performs each batch through its `etldb.repo` repositories, and the
/// audit reports read the batches back. [DqmAddress] is the address-validation audit written by all address mappings.
package com.idq.cli.core.target;
