package com.idq.cli.cli;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.Domain;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.mock.SampleData;
import com.idq.cli.workflow.MappingCatalog;
import com.idq.cli.workflow.WorkflowRunner;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.springframework.stereotype.Service;

/// The actions behind every CLI command and REST endpoint. Prerequisites (latch order) are enforced here so both
/// front ends behave the same.
@Service
public class EtlConsole {

    public record CommandHelp(String command, String description, String requires) {}

    public static final List<CommandHelp> MENU = List.of(
            new CommandHelp("show-menu", "Display the available commands", ""),
            new CommandHelp("show-domains", "Supported domains, sub-domains and their mappings (all sources)", ""),
            new CommandHelp("show-sources", "Supported source systems and their source tables", ""),
            new CommandHelp("latch-source-system", "Latch a source system (one at a time)", ""),
            new CommandHelp("unlatch-source-system", "Unlatch the source system", ""),
            new CommandHelp("show-latched-source", "Display the latched source system", ""),
            new CommandHelp("latch-domain", "Latch an additional domain", ""),
            new CommandHelp("unlatch-domain", "Unlatch a domain", ""),
            new CommandHelp("show-latched-domains", "Display the latched domains", ""),
            new CommandHelp("latch-target-table", "Latch a C_S_* target table", "latch-source-system"),
            new CommandHelp("unlatch-target-table", "Unlatch the target table", ""),
            new CommandHelp("show-source-mapping", "Mappings that load the latched target table", "latch-target-table"),
            new CommandHelp("latch-mapping", "Latch a mapping", "latch-target-table"),
            new CommandHelp("unlatch-mapping", "Unlatch the mapping", ""),
            new CommandHelp("show-sample-data", "Sample rows of the latched mapping's IdqMapInitQuery",
                    "latch-mapping"),
            new CommandHelp("fill-sample-mock-data", "Generate mock source rows (fill_sample_mock_data_<mapping>)",
                    "latch-mapping"),
            new CommandHelp("fill-sample-real-data", "Copy real sample rows (fill_sample_real_data_<mapping>)",
                    "latch-mapping"),
            new CommandHelp("run-etl", "Run the workflow of the latched source system", "latch-source-system"),
            new CommandHelp("run-unit-tests", "Run the PKEY unit test of the latched mapping", "latch-mapping"),
            new CommandHelp("help", "Built-in help of the shell", ""),
            new CommandHelp("exit", "Exit the CLI", ""));

    private final LatchState latch;
    private final MappingCatalog catalog;
    private final WorkflowRunner runner;
    private final SampleData sampleData;
    private final EtlSettings settings;

    public EtlConsole(LatchState latch, MappingCatalog catalog, WorkflowRunner runner, SampleData sampleData,
            EtlSettings settings) {
        this.latch = latch;
        this.catalog = catalog;
        this.runner = runner;
        this.sampleData = sampleData;
        this.settings = settings;
    }

    public LatchState latch() {
        return latch;
    }

    /// Domain -> sub-domain -> mappings across every source system.
    public Map<Domain, Map<SubDomain, List<String>>> domains() {
        var member = catalog.all().stream().collect(Collectors.groupingBy(MemberMapping::subDomain, TreeMap::new,
                Collectors.mapping(m -> m.info().name(), Collectors.toList())));
        var result = new LinkedHashMap<Domain, Map<SubDomain, List<String>>>();
        result.put(Domain.MEMBER, member);
        result.put(Domain.PROVIDER, Map.of());
        return result;
    }

    public record SourceView(SourceSystem source, String workflow, String description, List<String> sourceTables,
            List<String> targetTables) {}

    public List<SourceView> sources() {
        return java.util.Arrays.stream(SourceSystem.values()).map(s -> new SourceView(s, s.workflow, s.description,
                s.sourceTables, catalog.targetTables(s))).toList();
    }

    public String latchSource(String name) {
        var source = SourceSystem.valueOf(name.trim().toUpperCase());
        latch.latchSource(source);
        return "Latched source system " + source;
    }

    public String unlatchSource() {
        latch.unlatchSource();
        return "Source system unlatched";
    }

    public String latchTargetTable(String table) {
        var source = requireSource();
        var target = table.trim().toUpperCase();
        if (!catalog.targetTables(source).contains(target)) {
            throw new IllegalArgumentException(target + " is not a target of " + source + "; choose one of "
                    + catalog.targetTables(source));
        }
        latch.latchTargetTable(target);
        return "Latched target table " + target;
    }

    public String unlatchTargetTable() {
        latch.unlatchTargetTable();
        return "Target table unlatched";
    }

    public String latchDomain(String name) {
        latch.latchDomain(Domain.valueOf(name.trim().toUpperCase()));
        return "Latched domains " + latch.domains();
    }

    public String unlatchDomain(String name) {
        latch.unlatchDomain(Domain.valueOf(name.trim().toUpperCase()));
        return "Latched domains " + latch.domains();
    }

    public record MappingView(String seq, String mapping, SubDomain subDomain, List<String> targets,
            List<String> sourceTables, String doc) {}

    public List<MappingView> sourceMappings() {
        var source = requireSource();
        var target = latch.targetTable().orElseThrow(() -> new IllegalStateException("latch-target-table first"));
        return catalog.loading(source, target).stream().map(EtlConsole::view).toList();
    }

    public String latchMapping(String name) {
        var allowed = sourceMappings().stream().map(MappingView::mapping).toList();
        var match = allowed.stream().filter(name.trim()::equalsIgnoreCase).findFirst()
                .orElseThrow(() -> new IllegalArgumentException(
                        name + " does not load the latched target; choose one of " + allowed));
        latch.latchMapping(match);
        return "Latched mapping " + match;
    }

    public String unlatchMapping() {
        latch.unlatchMapping();
        return "Mapping unlatched";
    }

    /// First rows of the latched mapping's `IdqMapInitQuery`.
    public List<?> sampleData(int limit) {
        return requireMapping().fetchIdqMapInitQueryResults().stream().limit(limit).toList();
    }

    public String fillSampleMockData() {
        return sampleData.fillMock(requireMapping().info().name());
    }

    public String fillSampleRealData() {
        return sampleData.fillReal(requireMapping().info().name());
    }

    /// With `mock_data=true` the source tables are first filled by every mapping's mock-data function, so a run
    /// needs no manual inserts; with `mock_data=false` the workflow reads whatever the tables hold.
    public WorkflowRunner.WorkflowRun runEtl() {
        var source = requireSource();
        var mock = sampleData.fillMockAll(catalog.of(source).stream().map(m -> m.info().name()).toList());
        var run = runner.run(source);
        return new WorkflowRunner.WorkflowRun(run.source(), run.engine(), run.results(),
                Stream.concat(Stream.of(mock), run.output().stream()).toList());
    }

    public MappingResult runLatchedMapping() {
        return runner.runMapping(requireMapping());
    }

    public record TestRun(String command, int exitCode, List<String> output) {}

    /// Runs `<Source>PkeyTest#<mapping>_pkey_test` through the Maven wrapper of the project directory.
    public TestRun runUnitTests() {
        var mapping = requireMapping().info();
        var testClass = mapping.source().name().charAt(0) + mapping.source().name().substring(1).toLowerCase()
                + "PkeyTest";
        var wrapper = System.getProperty("os.name").toLowerCase().contains("win") ? "mvnw.cmd" : "./mvnw";
        var command = List.of(wrapper, "-q", "test", "-Dtest=" + testClass + "#" + mapping.name() + "_pkey_test");
        try {
            var builder = new ProcessBuilder(System.getProperty("os.name").toLowerCase().contains("win")
                    ? List.of("cmd.exe", "/c", String.join(" ", command)) : command)
                    .directory(new File(System.getProperty("user.dir"))).redirectErrorStream(true);
            var process = builder.start();
            var output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8).lines()
                    .filter(line -> !line.isBlank()).toList();
            return new TestRun(String.join(" ", command), process.waitFor(), output);
        } catch (IOException e) {
            return new TestRun(String.join(" ", command), -1, List.of(e.getMessage()));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return new TestRun(String.join(" ", command), -1, List.of("interrupted"));
        }
    }

    public Map<String, Object> settings() {
        return Map.of("etl_process", settings.etlProcess(), "mock_infacmd", settings.mockInfacmd(), "mock_data",
                settings.mockData());
    }

    static MappingView view(MemberMapping<?, ?> m) {
        var info = m.info();
        return new MappingView(info.seq(), info.name(), m.subDomain(), info.targets(), info.sourceTables(),
                info.doc());
    }

    private SourceSystem requireSource() {
        return latch.source().orElseThrow(() -> new IllegalStateException("latch-source-system first"));
    }

    private MemberMapping<?, ?> requireMapping() {
        var name = latch.mapping().orElseThrow(() -> new IllegalStateException("latch-mapping first"));
        return catalog.byName(name).orElseThrow();
    }
}
