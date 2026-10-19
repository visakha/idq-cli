package com.idq.cli.mock;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

/// Test-fixture writer for mock source rows. Columns that the table does not have are skipped, so the generators
/// stay valid against slightly different schema versions. Only rows inside the mock id ranges (or carrying the mock
/// marker) are ever deleted.
@Component
public class MockTables {

    public static final String MARKER = "IDQ_CLI_MOCK";

    private final NamedParameterJdbcTemplate jdbc;
    private final Map<String, Set<String>> columns = new ConcurrentHashMap<>();

    public MockTables(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public int insert(String table, Map<String, Object> row) {
        var known = columnsOf(table);
        var values = new LinkedHashMap<String, Object>();
        row.forEach((column, value) -> {
            if (known.contains(column.toUpperCase())) {
                values.put(column.toUpperCase(), value);
            }
        });
        if (values.isEmpty()) {
            return 0;
        }
        var sql = "INSERT INTO " + table + " (" + String.join(", ", values.keySet()) + ") VALUES ("
                + values.keySet().stream().map(c -> ":" + c).collect(Collectors.joining(", ")) + ")";
        return jdbc.update(sql, values);
    }

    public int insertAll(String table, List<Map<String, Object>> rows) {
        return rows.stream().mapToInt(row -> insert(table, row)).sum();
    }

    /// Deletes previously generated rows: `column BETWEEN from AND to`.
    public int deleteRange(String table, String column, long from, long to) {
        if (!columnsOf(table).contains(column)) {
            return 0;
        }
        return jdbc.update("DELETE FROM " + table + " WHERE " + column + " BETWEEN :f AND :t",
                Map.of("f", from, "t", to));
    }

    /// Deletes previously generated rows: `column = 'IDQ_CLI_MOCK'`.
    public int deleteMarked(String table, String markerColumn) {
        if (!columnsOf(table).contains(markerColumn)) {
            return 0;
        }
        return jdbc.update("DELETE FROM " + table + " WHERE " + markerColumn + " = :m", Map.of("m", MARKER));
    }

    public int execute(String sql, Map<String, ?> params) {
        return jdbc.update(sql, params);
    }

    public Set<String> columnsOf(String table) {
        return columns.computeIfAbsent(table.toUpperCase(), t -> Set.copyOf(jdbc.queryForList(
                "SELECT COLUMN_NAME FROM USER_TAB_COLUMNS WHERE TABLE_NAME = :t", Map.of("t", t), String.class)));
    }

    public static Map<String, Object> row(Object... keyValues) {
        var map = new HashMap<String, Object>();
        for (int i = 0; i < keyValues.length; i += 2) {
            map.put((String) keyValues[i], keyValues[i + 1]);
        }
        return map;
    }
}
