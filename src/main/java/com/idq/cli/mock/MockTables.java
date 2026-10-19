package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EntityBuilder;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.springframework.data.jdbc.core.JdbcAggregateTemplate;
import org.springframework.data.mapping.PersistentPropertyAccessor;
import org.springframework.data.relational.core.mapping.RelationalPersistentEntity;
import org.springframework.data.relational.core.mapping.Table;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

/// Test-fixture writer for mock source rows: entity records (`<Src>Sources`, `ReferenceTables`, ...) inserted through
/// Spring Data JDBC. Only rows inside the mock id ranges (or carrying the mock marker) are ever deleted.
///
/// Free-text values go through [#text] to get the `mock-data-pre-fix`; every statement can be [#record]ed as
/// replayable SQL for the audit reports.
@Component
public class MockTables {

    public static final String MARKER = "IDQ_CLI_MOCK";

    private static final DateTimeFormatter TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final Pattern PARAMETER = Pattern.compile(":(\\w+)");

    private final JdbcAggregateTemplate aggregates;
    private final NamedParameterJdbcTemplate jdbc;
    private final EtlSettings settings;
    private final Map<String, Map<String, Integer>> columns = new ConcurrentHashMap<>();
    private final ThreadLocal<List<String>> recorder = new ThreadLocal<>();

    public MockTables(JdbcAggregateTemplate aggregates, NamedParameterJdbcTemplate jdbc, EtlSettings settings) {
        this.aggregates = aggregates;
        this.jdbc = jdbc;
        this.settings = settings;
    }

    /// A free-text value (name, e-mail, street, city) with the `mock-data-pre-fix`: `Test_001-JaneDoe@gmail.com`.
    public String text(String value) {
        var prefix = settings.mockDataPrefix();
        return value == null || prefix.isBlank() ? value : prefix + "-" + value;
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

    public <R extends Record> R insert(EntityBuilder<R> row) {
        return insert(row.build());
    }

    /// Inserts one entity. Prefixed free text longer than its column is cut at the end, so the prefix survives.
    public <R extends Record> R insert(R row) {
        var fitted = fitted(row);
        var statements = recorder.get();
        if (statements != null) {
            statements.add(insertSql(fitted));
        }
        return aggregates.insert(fitted);
    }

    public <R extends Record> List<R> insertAll(List<R> rows) {
        return rows.stream().map(this::insert).toList();
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

    /// A `DELETE` that the range and marker helpers cannot express.
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

    private <R extends Record> R fitted(R row) {
        var prefix = settings.mockDataPrefix();
        if (prefix.isBlank()) {
            return row;
        }
        var lengths = columnsOf(row.getClass().getAnnotation(Table.class).value());
        var persistent = aggregates.getConverter().getMappingContext().getRequiredPersistentEntity(row.getClass());
        return EntityBuilder.from(row).map((component, value) -> {
            var column = persistent.getRequiredPersistentProperty(component.getName()).getColumnName()
                    .getReference().toUpperCase();
            return value instanceof String text && text.startsWith(prefix + "-") && lengths.containsKey(column)
                    ? fit(text, lengths.get(column)) : value;
        }).build();
    }

    static String fit(String text, int maxLength) {
        return text.length() <= maxLength ? text : text.substring(0, maxLength);
    }

    /// `INSERT INTO <table> (<all columns>) VALUES (<literals>);`, embedded column groups flattened.
    String insertSql(Record row) {
        var values = new LinkedHashMap<String, Object>();
        var context = aggregates.getConverter().getMappingContext();
        collect(context.getRequiredPersistentEntity(row.getClass()), row, "", values);
        return "INSERT INTO " + row.getClass().getAnnotation(Table.class).value() + " ("
                + String.join(", ", values.keySet()) + ") VALUES ("
                + values.values().stream().map(MockTables::literal).collect(Collectors.joining(", ")) + ");";
    }

    private void collect(RelationalPersistentEntity<?> entity, Object bean, String prefix, Map<String, Object> out) {
        PersistentPropertyAccessor<?> accessor = bean == null ? null : entity.getPropertyAccessor(bean);
        var context = aggregates.getConverter().getMappingContext();
        entity.forEach(property -> {
            var value = accessor == null ? null : accessor.getProperty(property);
            if (property.isEmbedded()) {
                collect(context.getRequiredPersistentEntity(property), value,
                        prefix + Objects.toString(property.getEmbeddedPrefix(), ""), out);
            } else {
                out.put((prefix + property.getColumnName().getReference()).toUpperCase(), value);
            }
        });
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
}
