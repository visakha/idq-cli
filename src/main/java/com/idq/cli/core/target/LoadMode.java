package com.idq.cli.core.target;

import java.util.Map;
import java.util.function.Function;

/// How a [TargetBatch] is applied to its table.
public sealed interface LoadMode<T> {

    /// IDQ "truncate target table": delete every row (only for whitelisted tables), then insert.
    record ReplaceAll<T>() implements LoadMode<T> {}

    /// IDQ pre-SQL `DELETE FROM t WHERE column = 'value'`, then insert.
    record ReplaceWhere<T>(String column, Object value) implements LoadMode<T> {}

    /// Plain insert.
    record Append<T>() implements LoadMode<T> {}

    /// IDQ update strategy `DD_DELETE`: delete the rows whose key columns match, nothing is inserted.
    record DeleteByKey<T>(Function<T, Map<String, Object>> key) implements LoadMode<T> {}
}
