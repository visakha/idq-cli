package com.idq.cli.core.target;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import org.springframework.data.relational.core.mapping.Table;

/// Rows for one target table plus the way they are loaded.
public record TargetBatch<T>(Class<T> entity, List<T> rows, LoadMode<T> mode) {

    public static <T> TargetBatch<T> replaceAll(Class<T> entity, List<T> rows) {
        return new TargetBatch<>(entity, rows, new LoadMode.ReplaceAll<>());
    }

    public static <T> TargetBatch<T> replaceWhere(Class<T> entity, String column, Object value, List<T> rows) {
        return new TargetBatch<>(entity, rows, new LoadMode.ReplaceWhere<>(column, value));
    }

    public static <T> TargetBatch<T> append(Class<T> entity, List<T> rows) {
        return new TargetBatch<>(entity, rows, new LoadMode.Append<>());
    }

    public static <T> TargetBatch<T> deleteByKey(Class<T> entity, List<T> rows,
            Function<T, Map<String, Object>> key) {
        return new TargetBatch<>(entity, rows, new LoadMode.DeleteByKey<>(key));
    }

    public String table() {
        return entity.getAnnotation(Table.class).value();
    }
}
