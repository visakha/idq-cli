package com.idq.cli.core;

import com.idq.cli.core.target.TargetWriter;
import com.idq.cli.domain.MemberMapping;
import java.time.Duration;
import java.time.Instant;
import java.util.List;

/// Fluent driver of one mapping run:
///
/// ```java
/// MappingFlow.of(mapping).read().transform(ctx).writeWith(writer);
/// ```
public final class MappingFlow {

    private MappingFlow() {}

    public static <I, L> Reader<I, L> of(MemberMapping<I, L> mapping) {
        return new Reader<>(mapping, Instant.now());
    }

    public record Reader<I, L>(MemberMapping<I, L> mapping, Instant started) {
        public Transformer<I, L> read() {
            return new Transformer<>(this, mapping.fetchIdqMapInitQueryResults(), mapping.fetchLookups());
        }
    }

    public record Transformer<I, L>(Reader<I, L> reader, List<I> rows, L lookups) {
        public Writer transform(EtlContext ctx) {
            return new Writer(reader.mapping().info().name(), reader.started(), rows.size(),
                    reader.mapping().transform(rows, lookups, ctx));
        }
    }

    public record Writer(String mapping, Instant started, int rowsRead, MappingOutput output) {
        public MappingResult writeWith(TargetWriter writer) {
            var written = writer.write(output);
            return new MappingResult(mapping, MappingResult.Status.SUCCEEDED, rowsRead, written,
                    output.badRecords().size(), Duration.between(started, Instant.now()), null);
        }
    }
}
