package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

/// Test-fixture writer for mock source rows. Columns that the table does not have are skipped, so the generators
/// stay valid against slightly different schema versions. Only rows inside the mock id ranges (or carrying the mock
/// marker) are ever deleted.
///
/// Free-text values are passed as [Text] and get the `mock-data-pre-fix`; every statement can be [#record]ed as
/// replayable SQL for the audit reports.
@Component
public class MockTables {

    public static final String MARKER = "IDQ_CLI_MOCK";

    private static final DateTimeFormatter TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final Pattern PARAMETER = Pattern.compile(":(\\w+)");

    private final NamedParameterJdbcTemplate jdbc;
    private final EtlSettings settings;
    private final Map<String, Map<String, Integer>> columns = new ConcurrentHashMap<>();
    private final ThreadLocal<List<String>> recorder = new ThreadLocal<>();

    /// A free-text mock value (name, e-mail, street, city) that carries the `mock-data-pre-fix`.
    public record Text(String value) {}

    public MockTables(NamedParameterJdbcTemplate jdbc, EtlSettings settings) {
        this.jdbc = jdbc;
        this.settings = settings;
    }

    public static Text text(String value) {
        return value == null ? null : new Text(value);
    }

    /// Runs `work` and returns the SQL of every statement it executed, ready to replay in SQL Developer.
    public List<String> record(Runnable work) {
        var statements = new ArrayList<String>();
        recorder.set(statements);
        try {
            work.run();
        } finally {
            recorder.remove();
        }
        return List.copyOf(statements);
    }

    public int insert(String table, Map<String, Object> row) {
        var known = columnsOf(table);
        var values = new LinkedHashMap<String, Object>();
        row.forEach((column, value) -> {
            var name = column.toUpperCase();
            if (known.containsKey(name)) {
                values.put(name, value instanceof Text text
                        ? prefixed(settings.mockDataPrefix(), text.value(), known.get(name)) : value);
            }
        });
        if (values.isEmpty()) {
            return 0;
        }
        var sql = "INSERT INTO " + table + " (" + String.join(", ", values.keySet()) + ") VALUES ("
                + values.keySet().stream().map(c -> ":" + c).collect(Collectors.joining(", ")) + ")";
        return execute(sql, values);
    }

    public int insertAll(String table, List<Map<String, Object>> rows) {
        return rows.stream().mapToInt(row -> insert(table, row)).sum();
    }

    /// Deletes previously generated rows: `column BETWEEN from AND to`.
    public int deleteRange(String table, String column, long from, long to) {
        if (!columnsOf(table).containsKey(column)) {
            return 0;
        }
        return execute("DELETE FROM " + table + " WHERE " + column + " BETWEEN :f AND :t", Map.of("f", from, "t", to));
    }

    /// Deletes previously generated rows: `column = 'IDQ_CLI_MOCK'`.
    public int deleteMarked(String table, String markerColumn) {
        if (!columnsOf(table).containsKey(markerColumn)) {
            return 0;
        }
        return execute("DELETE FROM " + table + " WHERE " + markerColumn + " = :m", Map.of("m", MARKER));
    }

    public int execute(String sql, Map<String, ?> params) {
        var statements = recorder.get();
        if (statements != null) {
            statements.add(sql(sql, params));
        }
        return jdbc.update(sql, params);
    }

    /// Column name to maximum character length (`DATA_LENGTH`).
    public Map<String, Integer> columnsOf(String table) {
        return columns.computeIfAbsent(table.toUpperCase(), t -> Map.copyOf(jdbc.query(
                "SELECT COLUMN_NAME, DATA_LENGTH FROM USER_TAB_COLUMNS WHERE TABLE_NAME = :t", Map.of("t", t),
                rs -> {
                    var lengths = new HashMap<String, Integer>();
                    while (rs.next()) {
                        lengths.put(rs.getString(1), rs.getInt(2));
                    }
                    return lengths;
                })));
    }

    /// `<prefix>-<value>`, shortened at the end to the column length so the prefix always survives.
    static String prefixed(String prefix, String value, int maxLength) {
        var text = prefix == null || prefix.isBlank() ? value : prefix + "-" + value;
        return text.length() <= maxLength ? text : text.substring(0, maxLength);
    }

    /// The statement with its named parameters replaced by SQL literals, terminated by `;`.
    static String sql(String sql, Map<String, ?> params) {
        var replaced = PARAMETER.matcher(sql.strip()).replaceAll(m -> params.containsKey(m.group(1))
                ? Matcher.quoteReplacement(literal(params.get(m.group(1)))) : Matcher.quoteReplacement(m.group()));
        return replaced + ";";
    }

    static String literal(Object value) {
        return switch (value) {
            case null -> "NULL";
            case Number number -> number.toString();
            case LocalDateTime time -> "TIMESTAMP '" + time.format(TIMESTAMP) + "'";
            default -> "'" + value.toString().replace("'", "''") + "'";
        };
    }

    public static Map<String, Object> row(Object... keyValues) {
        var map = new LinkedHashMap<String, Object>();
        for (int i = 0; i < keyValues.length; i += 2) {
            map.put((String) keyValues[i], keyValues[i + 1]);
        }
        return map;
    }
}
