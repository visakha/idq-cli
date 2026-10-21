package com.idq.cli.core.target;

import java.util.List;
import org.springframework.data.relational.core.mapping.Table;

/// Rows for one target table plus the way they are loaded.
public record TargetBatch<T>(Class<T> entity, List<T> rows, LoadMode<T> mode) {

    public static <T> TargetBatch<T> append(Class<T> entity, List<T> rows) {
        return new TargetBatch<>(entity, rows, new LoadMode.Append<>());
    }

    public String table() {
        return entity.getAnnotation(Table.class).value();
    }
}
