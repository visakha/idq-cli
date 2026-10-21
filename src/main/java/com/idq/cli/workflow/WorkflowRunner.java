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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/// Executes a source system's workflow with the engine selected by `etl_process`.
///
/// In Java mode every mapping runs in workflow order. A failing mapping is reported and the workflow continues
/// (the CLI only cares about the latched mapping; the others typically have empty sources).
///
/// In ORA_SP mode the `sp_ors_main_*` procedures run in the order of the workflow's run script ([OraSpRunner]). The
/// first failing procedure stops the run and the rest are `SKIPPED`, as `WHENEVER SQLERROR EXIT` does in the script.
///
/// Every run is recorded through [EtlAudit]: source tables, `IdqMapInitQuery` rows and target rows are published as
/// events and written to the `adhoc_runs_<SOURCE>` Markdown reports.
@Component
public class WorkflowRunner {

    private static final Logger log = LoggerFactory.getLogger(WorkflowRunner.class);

    private final MappingCatalog catalog;
    private final ReferenceLoader referenceLoader;
    private final IdqCommandRunner idq;
    private final OraSpRunner oraSp;
    private final EtlSettings settings;
    private final EtlAudit audit;
    private final ReportSettings reports;

    public WorkflowRunner(MappingCatalog catalog, ReferenceLoader referenceLoader, IdqCommandRunner idq,
            OraSpRunner oraSp, EtlSettings settings, EtlAudit audit, ReportSettings reports) {
        this.catalog = catalog;
        this.referenceLoader = referenceLoader;
        this.idq = idq;
        this.oraSp = oraSp;
        this.settings = settings;
        this.audit = audit;
        this.reports = reports;
    }

    public record WorkflowRun(SourceSystem source, EtlProcess engine, List<MappingResult> results,
            List<String> output) {}

    public WorkflowRun run(SourceSystem source) {
        return run(source, settings.etlProcess());
    }

    /// Runs the workflow with the given engine, whatever `etl_process` says (used by `compare-etl-process`).
    public WorkflowRun run(SourceSystem source, EtlProcess engine) {
        var mappings = catalog.of(source);
        return switch (engine) {
            case JAVA -> runJava(source, mappings);
            case IDQ -> runIdq(source, mappings);
            case ORA_SP -> runOraSp(source, mappings);
        };
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
        mappings.forEach(mapping -> trail.tablesAfter(mapping.info()));
        var output = withReportLine(source, outcome.output().stream());
        trail.completed(output);
        return new WorkflowRun(source, EtlProcess.IDQ, List.of(), output);
    }

    /// The procedures do the work. For each one that replaces a mapping of the catalog, the audit trail records the
    /// sources and `IdqMapInitQuery` rows before the call and the target tables after it. Procedures without a Java
    /// mapping (e.g. the ECI reactivation mappings) are called and reported in the output only.
    private WorkflowRun runOraSp(SourceSystem source, List<MemberMapping<?, ?>> mappings) {
        var trail = audit.start(source, EtlProcess.ORA_SP, now());
        var byName = mappings.stream().collect(Collectors.toMap(m -> m.info().name(), m -> m));
        var results = new ArrayList<MappingResult>();
        var failed = false;
        for (var procedure : oraSp.procedures(source)) {
            var mapping = byName.get(OraSpRunner.mappingName(procedure));
            MappingResult result;
            if (failed) {
                result = new MappingResult(OraSpRunner.mappingName(procedure), MappingResult.Status.SKIPPED, 0,
                        Map.of(), 0, Duration.ZERO, "not run: an earlier procedure failed");
            } else {
                if (mapping != null) {
                    trail.sources(mapping.info());
                    try {
                        trail.initQuery(mapping, mapping.fetchIdqMapInitQueryResults());
                    } catch (RuntimeException e) {
                        log.warn("{} IdqMapInitQuery failed: {}", mapping.info().name(), e.getMessage());
                    }
                }
                result = oraSp.call(procedure);
                failed = result.status() == MappingResult.Status.FAILED;
                if (mapping != null && !failed) {
                    trail.tablesAfter(mapping.info());
                }
            }
            log.info(result.summary());
            if (mapping != null) {
                trail.finished(mapping.info(), result);
            }
            results.add(result);
        }
        var output = withReportLine(source, results.stream().map(MappingResult::summary));
        trail.completed(output);
        return new WorkflowRun(source, EtlProcess.ORA_SP, List.copyOf(results), output);
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
        return Map.of("etl_process", settings.etlProcess(), "mock_infacmd", settings.mockInfacmd(), "mock_ora_sp",
                settings.mockOraSp());
    }
}
