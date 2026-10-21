package com.idq.cli.workflow;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import com.idq.cli.config.ReportSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.MappingFlow;
import com.idq.cli.core.MappingResult;
import com.idq.cli.core.audit.EtlAudit;
import com.idq.cli.core.reference.ReferenceLoader;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceSystem;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/// Executes a source system's workflow with the engine selected by `etl_process`.
///
/// In Java mode every mapping runs in workflow order. A failing mapping is reported and the workflow continues
/// (the CLI only cares about the latched mapping; the others typically have empty sources).
///
/// Every run is recorded through [EtlAudit]: source tables, `IdqMapInitQuery` rows and target rows are published as
/// events and written to the `adhoc_runs_<SOURCE>` Markdown reports.
@Component
public class WorkflowRunner {

    private static final Logger log = LoggerFactory.getLogger(WorkflowRunner.class);

    private final MappingCatalog catalog;
    private final ReferenceLoader referenceLoader;
    private final IdqCommandRunner idq;
    private final EtlSettings settings;
    private final EtlAudit audit;
    private final ReportSettings reports;

    public WorkflowRunner(MappingCatalog catalog, ReferenceLoader referenceLoader, IdqCommandRunner idq,
            EtlSettings settings, EtlAudit audit, ReportSettings reports) {
        this.catalog = catalog;
        this.referenceLoader = referenceLoader;
        this.idq = idq;
        this.settings = settings;
        this.audit = audit;
        this.reports = reports;
    }

    public record WorkflowRun(SourceSystem source, EtlProcess engine, List<MappingResult> results,
            List<String> output) {}

    public WorkflowRun run(SourceSystem source) {
        var mappings = catalog.of(source);
        return settings.etlProcess() == EtlProcess.IDQ ? runIdq(source, mappings) : runJava(source, mappings);
    }

    /// Runs a single mapping (Java engine only).
    public MappingResult runMapping(MemberMapping<?, ?> mapping) {
        return runJava(mapping.info().source(), List.of(mapping)).results().getFirst();
    }

    private WorkflowRun runJava(SourceSystem source, List<MemberMapping<?, ?>> mappings) {
        var reference = referenceLoader.load();
        var runStart = now();
        var trail = audit.start(source, EtlProcess.JAVA, runStart);
        var results = mappings.stream()
                .map(mapping -> runOne(mapping, new EtlContext(mapping.info(), runStart, reference), trail))
                .toList();
        var output = withReportLine(source, results.stream().map(MappingResult::summary));
        trail.completed(output);
        return new WorkflowRun(source, EtlProcess.JAVA, results, output);
    }

    /// Informatica does the work; the audit trail records the sources and `IdqMapInitQuery` rows before the
    /// workflow and the target tables after it.
    private WorkflowRun runIdq(SourceSystem source, List<MemberMapping<?, ?>> mappings) {
        var trail = audit.start(source, EtlProcess.IDQ, now());
        mappings.forEach(mapping -> {
            trail.sources(mapping.info());
            try {
                trail.initQuery(mapping, mapping.fetchIdqMapInitQueryResults());
            } catch (RuntimeException e) {
                log.warn("{} IdqMapInitQuery failed: {}", mapping.info().name(), e.getMessage());
            }
        });
        var outcome = idq.startWorkflow(source);
        mappings.forEach(mapping -> trail.tablesAfterIdq(mapping.info()));
        var output = withReportLine(source, outcome.output().stream());
        trail.completed(output);
        return new WorkflowRun(source, EtlProcess.IDQ, List.of(), output);
    }

    private MappingResult runOne(MemberMapping<?, ?> mapping, EtlContext ctx, EtlAudit.Run trail) {
        var started = Instant.now();
        MappingResult result;
        try {
            trail.sources(mapping.info());
            var transformed = MappingFlow.of(mapping).read().peek(rows -> trail.initQuery(mapping, rows))
                    .transform(ctx);
            result = transformed.load();
            trail.written(mapping.info(), transformed.output());
            log.info(result.summary());
        } catch (RuntimeException e) {
            log.warn("{} failed: {}", mapping.info().name(), e.getMessage());
            result = MappingResult.failed(mapping.info().name(), Duration.between(started, Instant.now()), e);
        }
        trail.finished(mapping.info(), result);
        return result;
    }

    private List<String> withReportLine(SourceSystem source, Stream<String> output) {
        return Stream.concat(output, reports.enabled()
                ? Stream.of("Audit reports: " + reports.dirFor(source).toAbsolutePath().normalize())
                : Stream.empty()).toList();
    }

    private static LocalDateTime now() {
        return LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS);
    }

    public Map<String, Object> describe() {
        return Map.of("etl_process", settings.etlProcess(), "mock_infacmd", settings.mockInfacmd());
    }
}
