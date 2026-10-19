package com.idq.cli.core;

import com.idq.cli.core.target.StagingRow;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.function.Function;
import java.util.function.Predicate;

/// Row-set operations that stand in for IDQ sorter, aggregator and filter transformations.
public final class Rows {

    private Rows() {}

    /// IDQ aggregator grouped by `key` without aggregate functions: one row per key, the last one read wins.
    public static <T, K> List<T> lastPerKey(Collection<T> rows, Function<T, K> key) {
        var byKey = new LinkedHashMap<K, T>();
        rows.forEach(row -> byKey.put(key.apply(row), row));
        return List.copyOf(byKey.values());
    }

    /// Consolidation used by most mappings: distinct rows, then per `PKEY_SRC_OBJECT` the row with the latest
    /// period start. (The IDQ version ranking that went with it belongs to the retired MDM timeline.)
    public static <R extends StagingRow<?>> List<R> latestPerKey(Collection<R> rows) {
        return lastPerKey(sorted(distinct(rows), Rows.<R, String>asc(StagingRow::pkeySrcObject)
                .thenComparing(asc(r -> r.audit().periodStartDate()))), StagingRow::pkeySrcObject);
    }

    /// Relationship consolidation without the retired timeline: distinct segments ordered by key, end date (open
    /// segments last) and start date; the last segment per key is kept.
    public static <R extends StagingRow<?>> List<R> currentSegmentPerKey(Collection<R> rows) {
        return lastPerKey(sorted(distinct(rows), Rows.<R, String>asc(StagingRow::pkeySrcObject)
                .thenComparing(asc(r -> r.audit().periodEndDate()))
                .thenComparing(asc(r -> r.audit().periodStartDate()))), StagingRow::pkeySrcObject);
    }

    public static <T, K> List<T> firstPerKey(Collection<T> rows, Function<T, K> key) {
        var byKey = new LinkedHashMap<K, T>();
        rows.forEach(row -> byKey.putIfAbsent(key.apply(row), row));
        return List.copyOf(byKey.values());
    }

    /// IDQ sorter with the "distinct" option.
    public static <T> List<T> distinct(Collection<T> rows) {
        return rows.stream().distinct().toList();
    }

    public static <T> List<T> where(Collection<T> rows, Predicate<T> condition) {
        return rows.stream().filter(condition).toList();
    }

    public static <T> List<T> sorted(Collection<T> rows, Comparator<T> order) {
        return rows.stream().sorted(order).toList();
    }

    /// Ascending on a nullable key with nulls sorted high, the IDQ sorter default.
    public static <T, U extends Comparable<? super U>> Comparator<T> asc(Function<T, U> key) {
        return Comparator.comparing(key, Comparator.nullsLast(Comparator.naturalOrder()));
    }

    public static <T, U extends Comparable<? super U>> Comparator<T> desc(Function<T, U> key) {
        return Comparator.comparing(key, Comparator.nullsLast(Comparator.<U>naturalOrder()).reversed());
    }
}
