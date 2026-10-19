package com.idq.cli.workflow;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.MappingFlow;
import com.idq.cli.core.MappingResult;
import com.idq.cli.core.reference.ReferenceLoader;
import com.idq.cli.core.target.TargetWriter;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceSystem;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/// Executes a source system's workflow with the engine selected by `etl_process`.
///
/// In Java mode every mapping runs in workflow order. A failing mapping is reported and the workflow continues
/// (the CLI only cares about the latched mapping; the others typically have empty sources).
@Component
public class WorkflowRunner {

    private static final Logger log = LoggerFactory.getLogger(WorkflowRunner.class);

    private final MappingCatalog catalog;
    private final ReferenceLoader referenceLoader;
    private final TargetWriter writer;
    private final IdqCommandRunner idq;
    private final EtlSettings settings;

    public WorkflowRunner(MappingCatalog catalog, ReferenceLoader referenceLoader, TargetWriter writer,
            IdqCommandRunner idq, EtlSettings settings) {
        this.catalog = catalog;
        this.referenceLoader = referenceLoader;
        this.writer = writer;
        this.idq = idq;
        this.settings = settings;
    }

    public record WorkflowRun(SourceSystem source, EtlProcess engine, List<MappingResult> results,
            List<String> output) {}

    public WorkflowRun run(SourceSystem source) {
        if (settings.etlProcess() == EtlProcess.IDQ) {
            var outcome = idq.startWorkflow(source);
            return new WorkflowRun(source, EtlProcess.IDQ, List.of(), outcome.output());
        }
        var reference = referenceLoader.load();
        var runStart = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS);
        var results = catalog.of(source).stream()
                .map(mapping -> runOne(mapping, new EtlContext(mapping.info(), runStart, reference)))
                .toList();
        return new WorkflowRun(source, EtlProcess.JAVA, results, results.stream().map(MappingResult::summary).toList());
    }

    /// Runs a single mapping (Java engine only).
    public MappingResult runMapping(MemberMapping<?, ?> mapping) {
        return runOne(mapping, new EtlContext(mapping.info(), LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS),
                referenceLoader.load()));
    }

    private MappingResult runOne(MemberMapping<?, ?> mapping, EtlContext ctx) {
        var started = Instant.now();
        try {
            var result = MappingFlow.of(mapping).read().transform(ctx).writeWith(writer);
            log.info(result.summary());
            return result;
        } catch (RuntimeException e) {
            log.warn("{} failed: {}", mapping.info().name(), e.getMessage());
            return MappingResult.failed(mapping.info().name(), Duration.between(started, Instant.now()), e);
        }
    }

    public Map<String, Object> describe() {
        return Map.of("etl_process", settings.etlProcess(), "mock_infacmd", settings.mockInfacmd());
    }
}
