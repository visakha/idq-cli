package com.idq.cli.core.target;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.MappingOutput;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.data.jdbc.core.JdbcAggregateTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/// Applies a [MappingOutput] to the database: Spring Data JDBC inserts, plus the row deletes IDQ performs before a
/// load. Tables are never dropped; emptying a table requires it to be on the clearable whitelist.
@Component
public class TargetWriter {

    private final JdbcAggregateTemplate aggregates;
    private final NamedParameterJdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final EtlSettings settings;

    public TargetWriter(JdbcAggregateTemplate aggregates, NamedParameterJdbcTemplate jdbc, TransactionTemplate tx,
            EtlSettings settings) {
        this.aggregates = aggregates;
        this.jdbc = jdbc;
        this.tx = tx;
        this.settings = settings;
    }

    /// @return rows inserted (or deleted) per table, in load order
    public Map<String, Integer> write(MappingOutput output) {
        var counts = new LinkedHashMap<String, Integer>();
        tx.executeWithoutResult(_ -> output.batches().forEach(batch -> counts.merge(batch.table(), apply(batch),
                Integer::sum)));
        return counts;
    }

    private <T> int apply(TargetBatch<T> batch) {
        var table = batch.table();
        switch (batch.mode()) {
            case LoadMode.ReplaceAll<T> _ -> clear(table);
            case LoadMode.ReplaceWhere<T> where -> jdbc.update(
                    "DELETE FROM " + table + " WHERE " + where.column() + " = :value", Map.of("value", where.value()));
            case LoadMode.Append<T> _ -> { }
            case LoadMode.DeleteByKey<T> delete -> {
                return batch.rows().stream().mapToInt(row -> deleteMatching(table, delete.key().apply(row))).sum();
            }
        }
        aggregates.insertAll(batch.rows());
        return batch.rows().size();
    }

    private void clear(String table) {
        if (!settings.mayClear(table)) {
            throw new IllegalStateException(table + " is not on the clearable-tables whitelist; refusing to empty it");
        }
        jdbc.update("DELETE FROM " + table, Map.of());
    }

    private int deleteMatching(String table, Map<String, Object> key) {
        var where = key.keySet().stream().map(column -> column + " = :" + column)
                .collect(Collectors.joining(" AND "));
        return jdbc.update("DELETE FROM " + table + " WHERE " + where, key);
    }
}
