/// Spring Data JDBC records of the MDM `C_S_*` staging tables, one holder per source system: [EciTargets],
/// [FssTargets], [TrsTargets], [TtfTargets], [WicTargets].
///
/// Why it exists: the `C_S_<SRC>_*` tables belong to MDM, not to the source system that fills them. Each record is
/// the formulated key (`PKEY_SRC_OBJECT`), the common MDM columns (`core.target.MdmAudit`) and one sub-domain column
/// group (`core.target.Columns`), so all sources share the same shape. The source-specific mapping services in
/// `source.<src>.etlmap.svc` build these rows; the workflow tables they also write (`STG_*`) stay in
/// `source.<src>.etldb.models`.
package com.idq.cli.mdmdc.etldb.models;
