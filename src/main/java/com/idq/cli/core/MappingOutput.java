package com.idq.cli.core;

import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.target.TargetBatch;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

/// What a mapping run loads: target batches in IDQ load order, plus the rows routed to `EXC_STG_BAD_REC_MEMB`.
public record MappingOutput(List<TargetBatch<?>> targets, List<BadRecord> badRecords) {

    public static MappingOutput empty() {
        return new MappingOutput(List.of(), List.of());
    }

    public MappingOutput load(TargetBatch<?> batch) {
        var all = new ArrayList<TargetBatch<?>>(targets);
        all.add(batch);
        return new MappingOutput(List.copyOf(all), badRecords);
    }

    public MappingOutput reject(List<BadRecord> rejected) {
        return new MappingOutput(targets, Stream.concat(badRecords.stream(), rejected.stream()).toList());
    }

    /// Target batches followed by the exception rows (appended, never cleared).
    public List<TargetBatch<?>> batches() {
        return badRecords.isEmpty() ? targets
                : Stream.concat(targets.stream(), Stream.of(TargetBatch.append(BadRecord.class, badRecords))).toList();
    }

    /// Batches bound for one table, in load order.
    @SuppressWarnings("unchecked")
    public <T> List<TargetBatch<T>> batches(Class<T> entity) {
        return targets.stream().filter(b -> b.entity() == entity).map(b -> (TargetBatch<T>) b).toList();
    }

    /// Rows bound for one table.
    @SuppressWarnings("unchecked")
    public <T> List<T> rows(Class<T> entity) {
        return targets.stream().filter(b -> b.entity() == entity).flatMap(b -> ((List<T>) b.rows()).stream())
                .toList();
    }
}
