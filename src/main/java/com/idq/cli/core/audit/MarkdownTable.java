package com.idq.cli.core.audit;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.springframework.data.relational.core.mapping.RelationalMappingContext;
import org.springframework.data.relational.core.mapping.RelationalPersistentEntity;

/// Renders entity records as an ASCII Markdown table. Embedded records (`MdmAudit`, `Columns.*`, composite keys) are
/// flattened and headers are the database column names, so a report reads like a query result in SQL Developer.
///
/// Columns and values come from Spring Data's mapping metadata: the same column names (`@Column` or the naming
/// strategy) that Spring Data JDBC reads and writes.
public final class MarkdownTable {

    private static final DateTimeFormatter TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private record Cell(String header, Function<Object, Object> value) {}

    private final RelationalMappingContext mapping;

    public MarkdownTable(RelationalMappingContext mapping) {
        this.mapping = mapping;
    }

    public String of(Class<?> type, List<?> rows) {
        if (rows.isEmpty()) {
            return "_no rows_\n";
        }
        var cells = type != null && type.isRecord()
                ? cells(mapping.getRequiredPersistentEntity(type), "", Function.identity())
                : List.of(new Cell("VALUE", Function.identity()));
        var lines = new ArrayList<String>();
        lines.add(line(cells.stream().map(Cell::header)));
        lines.add(line(cells.stream().map(_ -> "---")));
        rows.forEach(row -> lines.add(line(cells.stream().map(cell -> format(cell.value().apply(row))))));
        return String.join("\n", lines) + "\n";
    }

    private List<Cell> cells(RelationalPersistentEntity<?> entity, String prefix, Function<Object, Object> owner) {
        var cells = new ArrayList<Cell>();
        entity.forEach(property -> {
            Function<Object, Object> value = row -> {
                var parent = owner.apply(row);
                return parent == null ? null : entity.getPropertyAccessor(parent).getProperty(property);
            };
            if (property.isEntity()) {
                cells.addAll(cells(mapping.getRequiredPersistentEntity(property),
                        prefix + Objects.toString(property.getEmbeddedPrefix(), ""), value));
            } else {
                cells.add(new Cell((prefix + property.getColumnName().getReference()).toUpperCase(), value));
            }
        });
        return cells;
    }

    private static String line(Stream<String> values) {
        return values.collect(Collectors.joining(" | ", "| ", " |"));
    }

    /// Plain ASCII only: pipes escaped, line breaks flattened, anything else outside printable ASCII becomes `?`.
    public static String format(Object value) {
        var text = switch (value) {
            case null -> "";
            case LocalDateTime time -> time.format(TIMESTAMP);
            case BigDecimal number -> number.toPlainString();
            default -> value.toString();
        };
        return text.replaceAll("[\\r\\n\\t]+", " ").replaceAll("[^\\x20-\\x7E]", "?").replace("|", "\\|");
    }
}
