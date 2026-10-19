package com.idq.cli.core.audit;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import java.time.LocalDateTime;
import java.util.List;

/// Diagnostic and audit events of a workflow run, published through Spring's `ApplicationEventPublisher`.
///
/// Order within one run: [RunStarted], then per mapping [SourceTablesCaptured], [InitQueryCaptured],
/// [TargetsWritten] and [MappingFinished], and finally [RunCompleted].
public sealed interface EtlEvent {

    RunId run();

    record RunId(SourceSystem source, EtlProcess engine, LocalDateTime started) {}

    /// Rows of one table or query: the total count and the first rows (up to `idq.report.max-rows`).
    ///
    /// @param entity Spring Data JDBC entity (or `IdqMapInitQuery` record) the rows are mapped to
    /// @param note   how the rows were obtained, shown under the section heading
    record RowSample(String name, Class<?> entity, long total, List<?> rows, String note) {}

    record RunStarted(RunId run) implements EtlEvent {}

    /// The mapping's source tables just before it runs.
    record SourceTablesCaptured(RunId run, MappingInfo mapping, List<RowSample> tables) implements EtlEvent {}

    /// What the mapping's `IdqMapInitQuery` returned.
    record InitQueryCaptured(RunId run, MappingInfo mapping, RowSample rows) implements EtlEvent {}

    /// The target rows after the load, one sample per table (including `EXC_STG_BAD_REC_MEMB`).
    record TargetsWritten(RunId run, MappingInfo mapping, List<RowSample> tables) implements EtlEvent {}

    record MappingFinished(RunId run, MappingInfo mapping, MappingResult result) implements EtlEvent {}

    record RunCompleted(RunId run, List<String> output) implements EtlEvent {}
}
