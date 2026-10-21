/// The data-quality exception queue `EXC_STG_BAD_REC_MEMB`, shared by every member mapping.
///
/// Why it exists: IDQ does not drop a bad row silently; it writes an exception row (invalid SSN, missing name,
/// unknown code, ...) and, depending on the rule, still loads or skips the target row. [BadRecords] builds those rows
/// the way the IDQ exception targets do; [BadRecordRepository] appends them.
package com.idq.cli.core.exception;
