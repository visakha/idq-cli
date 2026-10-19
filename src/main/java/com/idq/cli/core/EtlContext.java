package com.idq.cli.core;

import com.idq.cli.core.exception.BadRecords;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.reference.ReferenceData;
import com.idq.cli.domain.MappingInfo;
import java.time.LocalDateTime;

/// Everything a transformation needs besides its input rows.
///
/// @param runStart  IDQ `$sys.MappingRunStartTime`; also used for `SYSTIMESTAMP()` / `SYSDATE` so a run is
///                  reproducible
/// @param reference cached lookup tables
public record EtlContext(MappingInfo mapping, LocalDateTime runStart, ReferenceData reference) {

    public String mappingName() {
        return mapping.name();
    }

    public String sourceSystem() {
        return mapping.source().name();
    }

    /// A new `EXC_STG_BAD_REC_MEMB` row for this mapping run.
    public BadRecords badRecord() {
        return BadRecords.of(sourceSystem(), mappingName(), runStart);
    }

    public ExceptionInfo exception(String code) {
        return ExceptionInfo.of(code, reference);
    }
}
