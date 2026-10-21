package com.idq.cli.core.audit;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.ReportSettings;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.MappingResult;
import com.idq.cli.core.audit.EtlEvent.RowSample;
import com.idq.cli.core.audit.EtlEvent.RunId;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.target.LoadMode;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceSystem;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Supplier;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.jdbc.core.JdbcAggregateTemplate;
import org.springframework.data.relational.core.query.Query;
import org.springframework.stereotype.Component;

/// Captures what a workflow run reads and writes and publishes it as [EtlEvent]s.
///
/// Everything is read through the Spring Data JDBC entities: source tables via their `@Table` records, the
/// `IdqMapInitQuery` via its named-query record and targets read back by their `@Id` (`PKEY_SRC_OBJECT`).
/// Capturing never fails a run: a table that cannot be read is reported with the error instead.
@Component
public class EtlAudit {

    private final ApplicationEventPublisher events;
    private final JdbcAggregateTemplate aggregates;
    private final ReportSettings settings;

    public EtlAudit(ApplicationEventPublisher events, JdbcAggregateTemplate aggregates, ReportSettings settings) {
        this.events = events;
        this.aggregates = aggregates;
        this.settings = settings;
    }

    public Run start(SourceSystem source, EtlProcess engine, LocalDateTime started) {
        var run = new Run(new RunId(source, engine, started));
        run.publish(new EtlEvent.RunStarted(run.id));
        return run;
    }

    /// One workflow run. Source snapshots are cached until a mapping of the run loads that table.
    public final class Run {

        public final RunId id;
        private final Map<String, RowSample> sourceCache = new HashMap<>();

        private Run(RunId id) {
            this.id = id;
        }

        public Run sources(MappingInfo mapping) {
            if (settings.enabled()) {
                publish(new EtlEvent.SourceTablesCaptured(id, mapping, mapping.sourceEntities().stream()
                        .map(entity -> sourceCache.computeIfAbsent(MappingInfo.table(entity), _ -> table(entity,
                                "rows in the table before the mapping ran")))
                        .toList()));
            }
            return this;
        }

        public Run initQuery(MemberMapping<?, ?> mapping, List<?> rows) {
            if (settings.enabled()) {
                publish(new EtlEvent.InitQueryCaptured(id, mapping.info(), new RowSample("IdqMapInitQuery",
                        mapping.rowType(),
                        rows.size(), head(rows), "rows returned by the IdqMapInitQuery")));
            }
            return this;
        }

        /// The Java engine's load: each batch read back from its table by key.
        public Run written(MappingInfo mapping, MappingOutput output) {
            if (settings.enabled()) {
                mapping.targetTables().forEach(sourceCache::remove);
                publish(new EtlEvent.TargetsWritten(id, mapping, output.batches().stream()
                        .map(EtlAudit.this::readBack).toList()));
            }
            return this;
        }

        /// The IDQ and ORA_SP engines' load: the whole content of each target table after the workflow (IDQ) or the
        /// mapping's stored procedure (ORA_SP).
        public Run tablesAfter(MappingInfo mapping) {
            if (settings.enabled()) {
                var note = id.engine() == EtlProcess.ORA_SP
                        ? "table content after the Oracle stored procedure (all rows)"
                        : "table content after the IDQ workflow (all rows)";
                mapping.targetTables().forEach(sourceCache::remove);
                publish(new EtlEvent.TargetsWritten(id, mapping, mapping.targets().stream()
                        .map(entity -> table(entity, note))
                        .toList()));
            }
            return this;
        }

        public Run finished(MappingInfo mapping, MappingResult result) {
            publish(new EtlEvent.MappingFinished(id, mapping, result));
            return this;
        }

        public void completed(List<String> output) {
            publish(new EtlEvent.RunCompleted(id, output));
        }

        private void publish(EtlEvent event) {
            if (settings.enabled()) {
                events.publishEvent(event);
            }
        }
    }

    private RowSample table(Class<?> entity, String note) {
        var name = MappingInfo.table(entity);
        return safely(name, entity, () -> new RowSample(name, entity, aggregates.count(entity),
                aggregates.findAll(Query.empty().limit(settings.maxRows()), entity), note));
    }

    private <T> RowSample readBack(TargetBatch<T> batch) {
        var entity = batch.entity();
        var persistent = aggregates.getConverter().getMappingContext().getRequiredPersistentEntity(entity);
        if (batch.mode() instanceof LoadMode.DeleteByKey<T> || entity == BadRecord.class) {
            var note = batch.mode() instanceof LoadMode.DeleteByKey<T> ? "rows deleted by key"
                    : "rows appended (the table has no key to read them back by)";
            return new RowSample(batch.table(), entity, batch.rows().size(), head(batch.rows()), note);
        }
        var ids = head(batch.rows()).stream()
                .map(row -> persistent.getIdentifierAccessor(row).getIdentifier())
                .filter(Objects::nonNull).distinct().toList();
        return safely(batch.table(), entity, () -> new RowSample(batch.table(), entity, batch.rows().size(),
                aggregates.findAllById(ids, entity), "rows loaded by this run, read back from the table by key"));
    }

    private <R> List<R> head(List<R> rows) {
        return rows.size() <= settings.maxRows() ? rows : rows.subList(0, settings.maxRows());
    }

    private static RowSample safely(String name, Class<?> entity, Supplier<RowSample> read) {
        try {
            return read.get();
        } catch (RuntimeException e) {
            return new RowSample(name, entity, 0, List.of(), "could not be read: " + e.getMessage());
        }
    }
}
