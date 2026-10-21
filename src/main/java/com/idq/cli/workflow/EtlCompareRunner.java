package com.idq.cli.workflow;

import com.idq.cli.config.CompareSettings;
import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import com.idq.cli.config.ReportSettings;
import com.idq.cli.core.MappingResult;
import com.idq.cli.core.audit.MarkdownTable;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceSystem;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/// `compare-etl-process`: runs a source system's workflow with `ORA_SP`, then with `IDQ`, on the same source data and
/// compares what each engine left in the target tables. No mock data is generated; the tables are used as they are.
///
/// Nothing is deleted, truncated or dropped: every table is only read (`SELECT *`), the engines do the writing.
///
/// Steps:
///
/// 1. Snapshot every table the workflow reads or loads (the source tables of [SourceSystem], the source entities and
///    target entities of the source's mappings).
/// 2. Run ORA_SP ([OraSpRunner]) and snapshot the target tables. The ORA_SP result of a table is the rows added
///    since step 1.
/// 3. Run IDQ ([IdqCommandRunner], the `infacmd` shell script, which waits for the workflow to finish) and snapshot
///    the target tables. The IDQ result is the rows added since step 2; when rows of step 2 are gone (the
///    Informatica target is set to "truncate target table"), it is the whole table.
/// 4. Check that the source tables still hold their step-1 rows, compare the two results and write the Markdown
///    report `<idq.report.base-dir>/compare_runs_<SOURCE>/<SOURCE>_ORA_SP_vs_IDQ_<time>.md`.
///
/// Rows are compared on every column except `idq.compare.ignore-columns`. Tables with `PKEY_SRC_OBJECT` pair the
/// unmatched rows by that key and list the differing columns; other tables are compared as multisets of rows.
@Component
public class EtlCompareRunner {

    private static final Logger log = LoggerFactory.getLogger(EtlCompareRunner.class);
    private static final String KEY = "PKEY_SRC_OBJECT";
    private static final DateTimeFormatter FILE_TIME = DateTimeFormatter.ofPattern("dd_MM_yyyy_h_mm_a", Locale.US);
    private static final DateTimeFormatter TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final MappingCatalog catalog;
    private final WorkflowRunner runner;
    private final JdbcTemplate jdbc;
    private final EtlSettings settings;
    private final CompareSettings compare;
    private final ReportSettings reports;

    public EtlCompareRunner(MappingCatalog catalog, WorkflowRunner runner, JdbcTemplate jdbc, EtlSettings settings,
            CompareSettings compare, ReportSettings reports) {
        this.catalog = catalog;
        this.runner = runner;
        this.jdbc = jdbc;
        this.settings = settings;
        this.compare = compare;
        this.reports = reports;
    }

    /// All rows of one table or view, as read by `SELECT *`; `error` is set when it could not be read.
    record TableSnapshot(String table, boolean baseTable, List<String> columns, List<Map<String, Object>> rows,
            String error) {

        boolean readable() {
            return error == null;
        }
    }

    /// Whether a source table still holds the rows it held before the ORA_SP run.
    public record SourceCheck(String table, int rowsBefore, int rowsAfterOraSp, int rowsAfterIdq,
            boolean changedByOraSp, boolean changedByIdq, String note) {

        public boolean unchanged() {
            return !changedByOraSp && !changedByIdq;
        }
    }

    /// One `PKEY_SRC_OBJECT` present in both results with different values.
    public record ColumnDiff(String key, String column, String oraSp, String idq) {}

    public record TableDiff(String table, int oraSpRows, int idqRows, int matched, List<Map<String, Object>> onlyOraSp,
            List<Map<String, Object>> onlyIdq, List<ColumnDiff> changed, int changedKeys, List<String> columns,
            String error) {

        public boolean same() {
            return error == null && onlyOraSp.isEmpty() && onlyIdq.isEmpty() && changedKeys == 0
                    && oraSpRows == idqRows;
        }
    }

    /// @param notes tables whose result is the whole table because an engine emptied it itself
    public record Comparison(SourceSystem source, LocalDateTime started, WorkflowRunner.WorkflowRun oraSp,
            WorkflowRunner.WorkflowRun idq, List<SourceCheck> sources, List<TableDiff> targets, List<String> notes,
            List<String> warnings, Path report) {

        public boolean same() {
            return targets.stream().allMatch(TableDiff::same);
        }

        public List<String> summary() {
            var lines = new ArrayList<String>();
            lines.add("ORA_SP vs IDQ for %s (%s): %s".formatted(source, source.workflow,
                    same() ? "target tables MATCH" : "target tables DIFFER"));
            warnings.forEach(w -> lines.add("WARNING: " + w));
            targets.forEach(t -> lines.add("  %-28s %s ORA_SP=%d IDQ=%d matched=%d onlyORA_SP=%d onlyIDQ=%d changed=%d%s"
                    .formatted(t.table(), t.same() ? "SAME" : "DIFF", t.oraSpRows(), t.idqRows(), t.matched(),
                            t.onlyOraSp().size(), t.onlyIdq().size(), t.changedKeys(),
                            t.error() == null ? "" : " error=" + t.error())));
            sources.stream().filter(s -> !s.unchanged())
                    .forEach(s -> lines.add("  source %s changed (%s)".formatted(s.table(), s.note())));
            lines.add("Comparison report: " + report.toAbsolutePath().normalize());
            return lines;
        }
    }

    public Comparison compare(SourceSystem source) {
        var started = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS);
        var mappings = catalog.of(source);
        var targetTables = mappings.stream().flatMap(m -> m.info().targetTables().stream())
                .map(String::toUpperCase).collect(Collectors.toCollection(LinkedHashSet::new));
        var sourceTables = Stream.concat(source.sourceTables.stream(),
                        mappings.stream().map(MemberMapping::info).flatMap(m -> m.sourceTables().stream()))
                .map(String::toUpperCase).filter(t -> !targetTables.contains(t))
                .collect(Collectors.toCollection(LinkedHashSet::new));

        var warnings = new ArrayList<String>();
        if (settings.mockOraSp()) {
            warnings.add("mock_ora_sp=true: the stored procedures were only simulated, start with -Dmock_ora_sp=false");
        }
        if (settings.mockInfacmd()) {
            warnings.add("mock_infacmd=true: the IDQ workflow was only simulated, start with -Dmock_infacmd=false");
        }

        log.info("compare-etl-process {}: snapshot of {} source and {} target tables", source, sourceTables.size(),
                targetTables.size());
        var before = snapshot(Stream.concat(sourceTables.stream(), targetTables.stream()).toList());

        log.info("compare-etl-process {}: running ORA_SP", source);
        var oraSp = runner.run(source, EtlProcess.ORA_SP);
        if (oraSp.results().stream().anyMatch(r -> r.status() == MappingResult.Status.FAILED)) {
            warnings.add("the ORA_SP run has a FAILED procedure; its targets are compared as they were left");
        }
        var afterOraSp = snapshot(targetTables);
        var sourcesAfterOraSp = snapshot(sourceTables);

        log.info("compare-etl-process {}: running IDQ", source);
        var idq = runner.run(source, EtlProcess.IDQ);
        var afterIdq = snapshot(targetTables);
        var sourcesAfterIdq = snapshot(sourceTables);

        var sourceChecks = sourceTables.stream().map(t -> check(t, before.get(t), sourcesAfterOraSp.get(t),
                sourcesAfterIdq.get(t))).toList();
        if (sourceChecks.stream().anyMatch(s -> !s.unchanged())) {
            warnings.add("a source table changed during a run; see the source-table check of the report");
        }
        var notes = new ArrayList<String>();
        var diffs = targetTables.stream().map(t -> {
            var oraSpRows = added(t, "ORA_SP", before.get(t), afterOraSp.get(t), notes);
            var idqRows = added(t, "IDQ", afterOraSp.get(t), afterIdq.get(t), notes);
            return diff(t, oraSpRows, idqRows);
        }).toList();
        var report = reportPath(source, started);
        var comparison = new Comparison(source, started, oraSp, idq, sourceChecks, diffs, List.copyOf(notes),
                List.copyOf(warnings), report);
        write(report, markdown(comparison));
        return comparison;
    }

    // ---- snapshots --------------------------------------------------------------------------------------------------

    private Map<String, TableSnapshot> snapshot(Collection<String> tables) {
        var result = new LinkedHashMap<String, TableSnapshot>();
        tables.forEach(table -> result.put(table, snapshot(table)));
        return result;
    }

    private TableSnapshot snapshot(String table) {
        var baseTable = isBaseTable(table);
        try {
            var columns = new ArrayList<String>();
            var rows = jdbc.query("SELECT * FROM " + table, rs -> {
                var meta = rs.getMetaData();
                for (int i = 1; i <= meta.getColumnCount(); i++) {
                    columns.add(meta.getColumnLabel(i).toUpperCase());
                }
                var list = new ArrayList<Map<String, Object>>();
                while (rs.next()) {
                    var row = new LinkedHashMap<String, Object>();
                    for (int i = 1; i <= columns.size(); i++) {
                        row.put(columns.get(i - 1),
                                org.springframework.jdbc.support.JdbcUtils.getResultSetValue(rs, i));
                    }
                    list.add(row);
                }
                return list;
            });
            return new TableSnapshot(table, baseTable, List.copyOf(columns), rows, null);
        } catch (RuntimeException e) {
            log.warn("compare-etl-process: cannot read {}: {}", table, e.getMessage());
            return new TableSnapshot(table, baseTable, List.of(), List.of(), e.getMessage());
        }
    }

    private boolean isBaseTable(String table) {
        try {
            var count = jdbc.queryForObject("SELECT COUNT(*) FROM USER_TABLES WHERE TABLE_NAME = ?", Integer.class,
                    table);
            return count != null && count > 0;
        } catch (RuntimeException e) {
            return false;
        }
    }

    /// The rows a run added to a table: `after` minus `before`, compared on all columns. When rows of `before` are
    /// missing from `after`, the engine emptied the table itself (Informatica "truncate target table"), so all of
    /// `after` is its result; a note says so.
    private static TableSnapshot added(String table, String engine, TableSnapshot before, TableSnapshot after,
            List<String> notes) {
        if (!before.readable() || !after.readable()) {
            return after;
        }
        var columns = after.columns();
        var afterCounts = counts(after.rows(), columns);
        var kept = unmatched(before.rows(), columns, afterCounts).isEmpty();
        if (!kept) {
            notes.add("%s: rows present before %s are gone (the engine emptied the table), so its whole content is the %s result"
                    .formatted(table, engine, engine));
            return after;
        }
        return new TableSnapshot(table, after.baseTable(), columns,
                unmatched(after.rows(), columns, counts(before.rows(), columns)), null);
    }

    private static boolean changed(TableSnapshot before, TableSnapshot after) {
        if (before == null || after == null || !before.readable() || !after.readable()) {
            return false;
        }
        return !counts(before.rows(), before.columns()).equals(counts(after.rows(), after.columns()));
    }

    private static SourceCheck check(String table, TableSnapshot before, TableSnapshot afterOraSp,
            TableSnapshot afterIdq) {
        var error = Stream.of(before, afterOraSp, afterIdq).filter(s -> s != null && !s.readable())
                .map(TableSnapshot::error).findFirst();
        var byOraSp = changed(before, afterOraSp);
        var byIdq = changed(before, afterIdq);
        var note = error.map(e -> "could not be read: " + e)
                .orElse(byOraSp || byIdq ? (byOraSp ? "changed by ORA_SP " : "") + (byIdq ? "changed by IDQ" : "")
                        : before.baseTable() ? "unchanged" : "unchanged (view)");
        return new SourceCheck(table, before.rows().size(), afterOraSp.rows().size(), afterIdq.rows().size(),
                byOraSp, byIdq, note.strip());
    }

    // ---- comparison ------------------------------------------------------------------------------------------------

    private TableDiff diff(String table, TableSnapshot oraSp, TableSnapshot idq) {
        if (!oraSp.readable() || !idq.readable()) {
            return new TableDiff(table, oraSp.rows().size(), idq.rows().size(), 0, List.of(), List.of(), List.of(), 0,
                    List.of(), Objects.requireNonNullElse(oraSp.error(), idq.error()));
        }
        var columns = oraSp.columns().stream().filter(compare::compared).toList();
        var oraCounts = counts(oraSp.rows(), columns);
        var idqCounts = counts(idq.rows(), columns);
        var onlyOra = unmatched(oraSp.rows(), columns, idqCounts);
        var onlyIdq = unmatched(idq.rows(), columns, oraCounts);
        int matched = oraSp.rows().size() - onlyOra.size();

        var changed = new ArrayList<ColumnDiff>();
        int changedKeys = 0;
        if (columns.contains(KEY)) {
            var oraByKey = byKey(onlyOra);
            var idqByKey = byKey(onlyIdq);
            for (var key : oraByKey.keySet().stream().filter(idqByKey::containsKey).toList()) {
                var left = oraByKey.get(key);
                var right = idqByKey.get(key);
                changedKeys++;
                for (var column : columns) {
                    var l = normalize(left.get(column));
                    var r = normalize(right.get(column));
                    if (!l.equals(r)) {
                        changed.add(new ColumnDiff(key, column, l, r));
                    }
                }
                onlyOra.remove(left);
                onlyIdq.remove(right);
            }
        }
        return new TableDiff(table, oraSp.rows().size(), idq.rows().size(), matched, onlyOra, onlyIdq, changed,
                changedKeys, columns, null);
    }

    private static Map<String, Map<String, Object>> byKey(List<Map<String, Object>> rows) {
        var result = new LinkedHashMap<String, Map<String, Object>>();
        rows.forEach(row -> result.putIfAbsent(normalize(row.get(KEY)), row));
        return result;
    }

    /// Rows of `rows` left over once every row also counted in `other` is matched off.
    private static List<Map<String, Object>> unmatched(List<Map<String, Object>> rows, List<String> columns,
            Map<String, Integer> other) {
        var remaining = new LinkedHashMap<>(other);
        var result = new ArrayList<Map<String, Object>>();
        for (var row : rows) {
            var signature = signature(row, columns);
            var left = remaining.getOrDefault(signature, 0);
            if (left > 0) {
                remaining.put(signature, left - 1);
            } else {
                result.add(row);
            }
        }
        return result;
    }

    private static Map<String, Integer> counts(List<Map<String, Object>> rows, List<String> columns) {
        var result = new LinkedHashMap<String, Integer>();
        rows.forEach(row -> result.merge(signature(row, columns), 1, Integer::sum));
        return result;
    }

    private static String signature(Map<String, Object> row, List<String> columns) {
        return columns.stream().map(c -> normalize(row.get(c))).collect(Collectors.joining("\u0001"));
    }

    /// Value as compared: numbers without trailing zeros, timestamps to the second, binary as hex.
    static String normalize(Object value) {
        return switch (value) {
            case null -> "";
            case BigDecimal number -> number.signum() == 0 ? "0" : number.stripTrailingZeros().toPlainString();
            case Number number -> new BigDecimal(number.toString()).stripTrailingZeros().toPlainString();
            case Timestamp time -> time.toLocalDateTime().truncatedTo(ChronoUnit.SECONDS).format(TIMESTAMP);
            case LocalDateTime time -> time.truncatedTo(ChronoUnit.SECONDS).format(TIMESTAMP);
            case java.sql.Date date -> date.toLocalDate().toString();
            case byte[] bytes -> HexFormat.of().formatHex(bytes);
            default -> value.toString();
        };
    }

    // ---- report ----------------------------------------------------------------------------------------------------

    private Path reportPath(SourceSystem source, LocalDateTime started) {
        var dir = reports.baseDir().resolve("compare_runs_" + source.name());
        var base = "%s_ORA_SP_vs_IDQ_%s".formatted(source.name(), started.format(FILE_TIME));
        var path = dir.resolve(base + ".md");
        for (int n = 2; Files.exists(path); n++) {
            path = dir.resolve(base + "_" + n + ".md");
        }
        return path;
    }

    private static void write(Path path, String content) {
        try {
            Files.createDirectories(path.getParent());
            Files.writeString(path, content, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("Cannot write the comparison report " + path.toAbsolutePath(), e);
        }
    }

    private String markdown(Comparison c) {
        var md = new StringBuilder();
        md.append("# ORA_SP vs IDQ - ").append(c.source()).append(" (").append(c.source().workflow).append(")\n\n");
        md.append("| | |\n|---|---|\n");
        md.append("| Started | ").append(c.started().format(TIMESTAMP)).append(" |\n");
        md.append("| Result | **").append(c.same() ? "target tables MATCH" : "target tables DIFFER").append("** |\n");
        md.append("| Order | ORA_SP first, then IDQ (infacmd) |\n");
        md.append("| mock_ora_sp / mock_infacmd | ").append(settings.mockOraSp()).append(" / ")
                .append(settings.mockInfacmd()).append(" |\n");
        md.append("| ORA_SP / IDQ result | rows each run added to the table (whole table if the engine emptied it) |\n");
        md.append("| Ignored columns | ").append(String.join(", ", compare.ignoreColumns().stream().sorted().toList()))
                .append(" |\n");
        md.append("| Rows shown per section | ").append(reports.maxRows()).append(" |\n\n");

        if (!c.warnings().isEmpty()) {
            md.append("## Warnings\n\n");
            c.warnings().forEach(w -> md.append("* ").append(w).append('\n'));
            md.append('\n');
        }

        md.append("## Target tables\n\n");
        md.append("| Table | Result | ORA_SP rows | IDQ rows | Matched | Only ORA_SP | Only IDQ | Changed keys |\n");
        md.append("|---|---|---|---|---|---|---|---|\n");
        c.targets().forEach(t -> md.append("| %s | %s | %d | %d | %d | %d | %d | %d |\n".formatted(t.table(),
                t.error() != null ? "ERROR" : t.same() ? "SAME" : "DIFF", t.oraSpRows(), t.idqRows(), t.matched(),
                t.onlyOraSp().size(), t.onlyIdq().size(), t.changedKeys())));
        md.append('\n');

        md.append("## Source tables (must be unchanged)\n\n");
        md.append("| Table | Rows before | After ORA_SP | After IDQ | Status |\n|---|---|---|---|---|\n");
        c.sources().forEach(s -> md.append("| %s | %d | %d | %d | %s |\n".formatted(s.table(), s.rowsBefore(),
                s.rowsAfterOraSp(), s.rowsAfterIdq(), MarkdownTable.format(s.note()))));
        md.append('\n');
        if (!c.notes().isEmpty()) {
            md.append("## Notes\n\n");
            c.notes().forEach(n -> md.append("* ").append(n).append('\n'));
            md.append('\n');
        }

        md.append("## Runs\n\n");
        run(md, "ORA_SP", c.oraSp());
        run(md, "IDQ", c.idq());

        c.targets().stream().filter(t -> !t.same()).forEach(t -> {
            md.append("## ").append(t.table()).append("\n\n");
            if (t.error() != null) {
                md.append("Could not be read: ").append(MarkdownTable.format(t.error())).append("\n\n");
                return;
            }
            if (!t.changed().isEmpty()) {
                md.append("### Changed rows (same ").append(KEY).append(", different values): ")
                        .append(t.changedKeys()).append(" keys\n\n");
                md.append("| ").append(KEY).append(" | Column | ORA_SP | IDQ |\n|---|---|---|---|\n");
                t.changed().stream().limit(reports.maxRows()).forEach(d -> md.append("| %s | %s | %s | %s |\n"
                        .formatted(MarkdownTable.format(d.key()), d.column(), MarkdownTable.format(d.oraSp()),
                                MarkdownTable.format(d.idq()))));
                md.append('\n');
            }
            rows(md, "Only in ORA_SP", t.onlyOraSp(), t.columns());
            rows(md, "Only in IDQ", t.onlyIdq(), t.columns());
        });
        return md.toString();
    }

    private static void run(StringBuilder md, String engine, WorkflowRunner.WorkflowRun run) {
        md.append("### ").append(engine).append("\n\n```text\n");
        run.output().forEach(line -> md.append(line).append('\n'));
        md.append("```\n\n");
    }

    private void rows(StringBuilder md, String title, List<Map<String, Object>> rows, List<String> columns) {
        if (rows.isEmpty()) {
            return;
        }
        md.append("### ").append(title).append(": ").append(rows.size()).append(" rows\n\n");
        md.append(columns.stream().collect(Collectors.joining(" | ", "| ", " |\n")));
        md.append(columns.stream().map(_ -> "---").collect(Collectors.joining(" | ", "| ", " |\n")));
        rows.stream().limit(reports.maxRows()).forEach(row -> md.append(columns.stream()
                .map(c -> MarkdownTable.format(normalize(row.get(c))))
                .collect(Collectors.joining(" | ", "| ", " |\n"))));
        if (rows.size() > reports.maxRows()) {
            md.append("\n_").append(rows.size() - reports.maxRows()).append(" more rows not shown_\n");
        }
        md.append('\n');
    }
}
