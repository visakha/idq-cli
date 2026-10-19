package com.idq.cli.core.audit;

import java.lang.reflect.RecordComponent;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.util.ReflectionUtils;

/// Renders entity records as an ASCII Markdown table. Embedded records (`MdmAudit`, `Columns.*`) are flattened and
/// headers are the database column names, so a report reads like a query result in SQL Developer.
public final class MarkdownTable {

    private static final DateTimeFormatter TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private record Cell(String header, Function<Object, Object> value) {}

    private MarkdownTable() {}

    public static String of(Class<?> type, List<?> rows) {
        if (rows.isEmpty()) {
            return "_no rows_\n";
        }
        var cells = type != null && type.isRecord() ? cells(type, Function.identity())
                : List.of(new Cell("VALUE", Function.identity()));
        var lines = new ArrayList<String>();
        lines.add(line(cells.stream().map(Cell::header)));
        lines.add(line(cells.stream().map(_ -> "---")));
        rows.forEach(row -> lines.add(line(cells.stream().map(cell -> format(cell.value().apply(row))))));
        return String.join("\n", lines) + "\n";
    }

    private static List<Cell> cells(Class<?> type, Function<Object, Object> owner) {
        return Arrays.stream(type.getRecordComponents()).flatMap(component -> {
            Function<Object, Object> value = row -> {
                var parent = owner.apply(row);
                return parent == null ? null : ReflectionUtils.invokeMethod(component.getAccessor(), parent);
            };
            return component.getType().isRecord() ? cells(component.getType(), value).stream()
                    : Stream.of(new Cell(column(component), value));
        }).toList();
    }

    static String column(RecordComponent component) {
        var column = component.getAccessor().getAnnotation(Column.class);
        return column != null ? column.value()
                : component.getName().replaceAll("([a-z0-9])([A-Z])", "$1_$2").toUpperCase();
    }

    private static String line(Stream<String> values) {
        return values.collect(Collectors.joining(" | ", "| ", " |"));
    }

    /// Plain ASCII only: pipes escaped, line breaks flattened, anything else outside printable ASCII becomes `?`.
    static String format(Object value) {
        var text = switch (value) {
            case null -> "";
            case LocalDateTime time -> time.format(TIMESTAMP);
            case BigDecimal number -> number.toPlainString();
            default -> value.toString();
        };
        return text.replaceAll("[\\r\\n\\t]+", " ").replaceAll("[^\\x20-\\x7E]", "?").replace("|", "\\|");
    }
}
