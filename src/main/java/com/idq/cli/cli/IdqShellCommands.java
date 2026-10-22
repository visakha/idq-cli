package com.idq.cli.cli;

import com.idq.cli.domain.SourceSystem;
import java.util.List;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import org.springframework.shell.core.command.CommandContext;
import org.springframework.shell.core.command.annotation.Argument;
import org.springframework.shell.core.command.annotation.Command;
import org.springframework.stereotype.Component;

/// Spring Shell commands. Each delegates to [EtlConsole]; the prompt shows the latched context.
@Component
public class IdqShellCommands {

    private static final String GROUP = "IDQ ETL";

    private final EtlConsole console;

    public IdqShellCommands(EtlConsole console) {
        this.console = console;
    }

    @Command(name = "show-menu", description = "Display the available CLI commands and options", group = GROUP)
    public String showMenu() {
        return EtlConsole.MENU.stream()
                .map(c -> "  %-24s %s%s".formatted(c.command(), c.description(),
                        c.requires().isEmpty() ? "" : "  [requires " + c.requires() + "]"))
                .collect(Collectors.joining("\n", "Commands  (" + console.settings() + ")\n", ""));
    }

    @Command(name = "show-domains", description = "Supported domains and their mappings", group = GROUP)
    public String showDomains() {
        var out = new StringBuilder();
        console.domains().forEach((domain, subDomains) -> {
            out.append(domain).append(subDomains.isEmpty() ? "  (not implemented)\n" : "\n");
            subDomains.forEach((sub, mappings) -> {
                out.append("  ").append(sub.label).append('\n');
                mappings.forEach(m -> out.append("    ").append(m).append('\n'));
            });
        });
        return out.toString().stripTrailing();
    }

    @Command(name = "show-sources", description = "Supported source systems and source tables", group = GROUP)
    public String showSources() {
        return console.sources().stream().map(s -> "%s  %s (%s)%n  source tables: %s%n  target tables: %s".formatted(
                s.source(), s.workflow(), s.description(), s.sourceTables(), s.targetTables()))
                .collect(Collectors.joining("\n"));
    }

    @Command(name = "latch-source-system", description = "Latch a source system: TRS, ECI, FSS, TTF, WIC or CRE",
            group = GROUP)
    public String latchSourceSystem(@Argument(index = 0, description = "source system") String source) {
        return attempt(() -> console.latchSource(source));
    }

    @Command(name = "unlatch-source-system", description = "Unlatch the source system", group = GROUP)
    public String unlatchSourceSystem() {
        return console.unlatchSource();
    }

    @Command(name = "show-latched-source", description = "Display the latched source system", group = GROUP)
    public String showLatchedSource() {
        return console.latch().source().map(Enum::name).orElse("No source system latched");
    }

    @Command(name = "latch-domain", description = "Latch a domain: MEMBER or PROVIDER", group = GROUP)
    public String latchDomain(@Argument(index = 0, description = "domain") String domain) {
        return attempt(() -> console.latchDomain(domain));
    }

    @Command(name = "unlatch-domain", description = "Unlatch a domain", group = GROUP)
    public String unlatchDomain(@Argument(index = 0, description = "domain") String domain) {
        return attempt(() -> console.unlatchDomain(domain));
    }

    @Command(name = "show-latched-domains", description = "Display the latched domains", group = GROUP)
    public String showLatchedDomains() {
        return console.latch().domains().toString();
    }

    @Command(name = "latch-target-table", description = "Latch a C_S_* target table of the latched source",
            group = GROUP)
    public String latchTargetTable(@Argument(index = 0, description = "target table") String table) {
        return attempt(() -> console.latchTargetTable(table));
    }

    @Command(name = "unlatch-target-table", description = "Unlatch the target table", group = GROUP)
    public String unlatchTargetTable() {
        return console.unlatchTargetTable();
    }

    @Command(name = "show-source-mapping", description = "Mappings for the latched source and target table",
            group = GROUP)
    public String showSourceMapping() {
        return attempt(() -> console.sourceMappings().stream()
                .map(m -> "  %s %-46s %-14s -> %s".formatted(m.seq(), m.mapping(), m.subDomain().label, m.targets()))
                .collect(Collectors.joining("\n")));
    }

    @Command(name = "latch-mapping", description = "Latch a mapping of the latched target table", group = GROUP)
    public String latchMapping(@Argument(index = 0, description = "mapping name") String mapping) {
        return attempt(() -> console.latchMapping(mapping));
    }

    @Command(name = "unlatch-mapping", description = "Unlatch the mapping", group = GROUP)
    public String unlatchMapping() {
        return console.unlatchMapping();
    }

    @Command(name = "show-sample-data", description = "Sample rows of the latched mapping's IdqMapInitQuery",
            group = GROUP)
    public String showSampleData() {
        return attempt(() -> {
            List<?> rows = console.sampleData(10);
            return rows.isEmpty() ? "No source rows (try fill-sample-mock-data)"
                    : rows.stream().map(Object::toString).collect(Collectors.joining("\n"));
        });
    }

    @Command(name = "fill-sample-mock-data", description = "Generate mock source rows for the latched mapping",
            group = GROUP)
    public String fillSampleMockData() {
        return attempt(console::fillSampleMockData);
    }

    @Command(name = "fill-sample-real-data", description = "Copy real sample rows for the latched mapping",
            group = GROUP)
    public String fillSampleRealData() {
        return attempt(console::fillSampleRealData);
    }

    @Command(name = "run-etl", description = "Run the workflow of the latched source system", group = GROUP)
    public String runEtl() {
        return attempt(() -> {
            var run = console.runEtl();
            return "Workflow %s (%s)%n%s".formatted(run.source().workflow, run.engine(),
                    String.join("\n", run.output()));
        });
    }

    @Command(name = "compare-etl-process",
            description = "Run ORA_SP then IDQ on the same source data and compare the target tables", group = GROUP)
    public String compareEtlProcess(
            @Argument(index = 0, description = "source system; prompted for when omitted", defaultValue = "")
            String source, CommandContext context) {
        return attempt(() -> {
            var chosen = source == null || source.isBlank() ? promptSource(context) : source;
            if (chosen.isBlank()) {
                return "No source system chosen";
            }
            return String.join("\n", console.compareEtlProcesses(chosen).summary());
        });
    }

    /// Lists the source systems and reads the choice (number or name); Enter keeps the latched source, if any.
    private String promptSource(CommandContext context) {
        var out = context.outputWriter();
        var latched = console.latch().source();
        out.println("Compare etl-process ORA_SP vs IDQ (no mock data; the source tables are left unchanged).");
        out.println("Source systems:");
        var values = SourceSystem.values();
        for (int i = 0; i < values.length; i++) {
            out.println("  %d) %-4s %s (%s)".formatted(i + 1, values[i], values[i].workflow, values[i].description));
        }
        out.flush();
        var prompt = "Choose a source system [1-%d]%s: ".formatted(values.length,
                latched.map(s -> " (Enter for " + s + ")").orElse(""));
        try {
            var answer = context.inputReader().readInput(prompt);
            return answer == null || answer.isBlank() ? latched.map(Enum::name).orElse("") : answer.strip();
        } catch (Exception e) {
            throw new IllegalStateException("cannot read the source system: " + e.getMessage(), e);
        }
    }

    @Command(name = "run-unit-tests", description = "Run the PKEY unit test of the latched mapping", group = GROUP)
    public String runUnitTests() {
        return attempt(() -> {
            var run = console.runUnitTests();
            return "%s%nexit code %d%n%s".formatted(run.command(), run.exitCode(), String.join("\n", run.output()));
        });
    }

    private static String attempt(Supplier<String> action) {
        try {
            return action.get();
        } catch (IllegalStateException | IllegalArgumentException e) {
            return "Not possible: " + e.getMessage();
        }
    }
}
