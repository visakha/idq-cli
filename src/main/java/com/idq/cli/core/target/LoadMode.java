package com.idq.cli.core.target;


/// How a [TargetBatch] is applied to its table. Rows are only ever inserted: no load mode deletes or truncates.
public sealed interface LoadMode<T> {

    /// Plain insert.
    record Append<T>() implements LoadMode<T> {}
}
