package com.idq.cli.core.audit;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.ReportSettings;
import com.idq.cli.core.MappingResult;
import com.idq.cli.core.audit.EtlEvent.RowSample;
import com.idq.cli.core.audit.EtlEvent.RunId;
import com.idq.cli.domain.MappingInfo;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/// Listens to the [EtlEvent]s of a run and, when it completes, writes one Markdown audit report per target table to
/// `adhoc_runs_<SOURCE>/<TABLE>_$<Java|IDQ>$_<dd_MM_yyyy_h_mm_AM>.md`.
///
/// A report shows, for every mapping that loads the table: the run outcome, the source tables, the rows of the
/// `IdqMapInitQuery`, the target rows and the data-quality exceptions.
@Component
public class AdhocRunReporter {

    private static final Logger log = LoggerFactory.getLogger(AdhocRunReporter.class);
    private static final DateTimeFormatter FILE_TIME = DateTimeFormatter.ofPattern("dd_MM_yyyy_h_mm_a", Locale.US);
    private static final DateTimeFormatter RUN_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final String EXCEPTIONS = "EXC_STG_BAD_REC_MEMB";

    private final ReportSettings settings;
    private final Map<RunId, Map<String, MappingLog>> runs = new ConcurrentHashMap<>();

    public AdhocRunReporter(ReportSettings settings) {
        this.settings = settings;
    }

    /// Everything captured for one mapping of a run.
    static final class MappingLog {
        final MappingInfo info;
        List<RowSample> sources = List.of();
        RowSample initQuery;
        List<RowSample> targets = List.of();
        MappingResult result;

        MappingLog(MappingInfo info) {
            this.info = info;
        }
    }

    public record Report(Path file, String markdown) {}

    @EventListener
    public void on(EtlEvent event) {
        switch (event) {
            case EtlEvent.RunStarted e -> runs.put(e.run(), new LinkedHashMap<>());
            case EtlEvent.SourceTablesCaptured e -> mapping(e.run(), e.mapping()).sources = e.tables();
            case EtlEvent.InitQueryCaptured e -> mapping(e.run(), e.mapping()).initQuery = e.rows();
            case EtlEvent.TargetsWritten e -> mapping(e.run(), e.mapping()).targets = e.tables();
            case EtlEvent.MappingFinished e -> mapping(e.run(), e.mapping()).result = e.result();
            case EtlEvent.RunCompleted e -> {
                var mappings = runs.remove(e.run());
                if (mappings != null) {
                    reports(e.run(), List.copyOf(mappings.values())).forEach(AdhocRunReporter::write);
                }
            }
        }
    }

    private MappingLog mapping(RunId run, MappingInfo info) {
        return runs.computeIfAbsent(run, _ -> new LinkedHashMap<>()).computeIfAbsent(info.name(),
                _ -> new MappingLog(info));
    }

    /// One report per target table, in workflow order.
    List<Report> reports(RunId run, List<MappingLog> mappings) {
        var byTable = new LinkedHashMap<String, List<MappingLog>>();
        mappings.forEach(m -> m.info.targets().forEach(t -> byTable.computeIfAbsent(t, _ -> new ArrayList<>())
                .add(m)));
        return byTable.entrySet().stream()
                .map(e -> new Report(file(run, e.getKey()), markdown(run, e.getKey(), e.getValue())))
                .toList();
    }

    Path file(RunId run, String table) {
        var name = "%s_$%s$_%s".formatted(table, engineLabel(run.engine()), run.started().format(FILE_TIME));
        var dir = settings.dirFor(run.source());
        return IntStream.iterate(1, i -> i + 1)
                .mapToObj(i -> dir.resolve(name + (i == 1 ? "" : "_" + i) + ".md"))
                .filter(path -> !Files.exists(path)).findFirst().orElseThrow();
    }

    static String engineLabel(EtlProcess engine) {
        return switch (engine) {
            case JAVA -> "Java";
            case IDQ -> "IDQ";
        };
    }

    String markdown(RunId run, String table, List<MappingLog> mappings) {
        var md = new StringBuilder();
        md.append("# ").append(table).append(" - ").append(run.source()).append(" adhoc run (")
                .append(engineLabel(run.engine())).append(")\n\n")
                .append("| item | value |\n| --- | --- |\n")
                .append("| source system | ").append(run.source()).append(" (").append(run.source().workflow)
                .append(") |\n")
                .append("| etl_process | ").append(run.engine()).append(" |\n")
                .append("| run started | ").append(run.started().format(RUN_TIME)).append(" |\n")
                .append("| rows shown per table | up to ").append(settings.maxRows()).append(" |\n\n")
                .append("## Mappings that load ").append(table).append("\n\n")
                .append("| seq | mapping | status | rows read | rows written | exceptions | ms | message |\n")
                .append("| --- | --- | --- | --- | --- | --- | --- | --- |\n");
        mappings.forEach(m -> md.append(summary(m)));
        mappings.forEach(m -> {
            md.append("\n## ").append(m.info.seq()).append(" ").append(m.info.name()).append("\n\n")
                    .append("Documentation: `").append(m.info.doc()).append("`\n\n")
                    .append("### Source tables\n\n");
            m.sources.forEach(sample -> section(md, "####", sample));
            if (m.sources.isEmpty()) {
                md.append("_not captured_\n\n");
            }
            if (m.initQuery != null) {
                section(md, "###", m.initQuery);
            }
            md.append("### Target ").append(table).append("\n\n");
            var targets = m.targets.stream().filter(s -> s.name().equalsIgnoreCase(table)).toList();
            targets.forEach(sample -> section(md, "####", sample));
            if (targets.isEmpty()) {
                md.append("_nothing loaded_\n\n");
            }
            m.targets.stream().filter(s -> s.name().equals(EXCEPTIONS) && s.total() > 0)
                    .forEach(sample -> section(md, "###", sample));
        });
        return md.toString();
    }

    private static String summary(MappingLog m) {
        var r = m.result;
        if (r == null) {
            return "| %s | %s | run by Informatica | | | | | |\n".formatted(m.info.seq(), m.info.name());
        }
        var written = r.rowsWritten().entrySet().stream().map(e -> e.getKey() + "=" + e.getValue())
                .collect(Collectors.joining(", "));
        return "| %s | %s | %s | %d | %s | %d | %d | %s |\n".formatted(m.info.seq(), m.info.name(), r.status(),
                r.rowsRead(), written, r.badRecords(), r.elapsed().toMillis(),
                r.message() == null ? "" : MarkdownTable.format(r.message()));
    }

    private static void section(StringBuilder md, String level, RowSample sample) {
        md.append(level).append(" ").append(sample.name());
        if (sample.entity() != null) {
            md.append(" (`").append(entityName(sample.entity())).append("`)");
        }
        md.append("\n\n").append(sample.total()).append(" rows, ").append(sample.rows().size()).append(" shown - ")
                .append(sample.note()).append("\n\n")
                .append(MarkdownTable.of(sample.entity(), sample.rows())).append("\n");
    }

    /// `EciQueries.FamilyRelation` rather than `com.idq.cli.source.eci.EciQueries$FamilyRelation`
    static String entityName(Class<?> type) {
        return type.getName().substring(type.getPackageName().length() + 1).replace('$', '.');
    }

    private static void write(Report report) {
        try {
            Files.createDirectories(report.file().getParent());
            Files.writeString(report.file(), report.markdown(), StandardCharsets.US_ASCII);
            log.info("Audit report {}", report.file());
        } catch (IOException e) {
            throw new UncheckedIOException("Cannot write audit report " + report.file(), e);
        }
    }
}
