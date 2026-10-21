package com.idq.cli.core;

import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.function.Supplier;

/// Hands a plain `source.<src>.etlmap.svc` service to the workflow runner, by method reference, so the service itself
/// implements no interface:
///
/// ```java
/// new ServiceMapping<>(EciAddressService.INFO, SubDomain.ADDRESS, FamilyAddress.class,
///         service::fetchFamilyAddresses, service::fetchDeactivatedParties, service::transform, service::load);
/// ```
public record ServiceMapping<I, L>(MappingInfo info, SubDomain subDomain, Class<I> rowType,
        Supplier<List<I>> initQuery, Supplier<L> lookups, Transformation<I, L> transformation,
        Function<MappingOutput, Map<String, Integer>> loader) implements MemberMapping<I, L> {

    @FunctionalInterface
    public interface Transformation<I, L> {
        MappingOutput apply(List<I> rows, L lookups, EtlContext ctx);
    }

    @Override
    public List<I> fetchIdqMapInitQueryResults() {
        return initQuery.get();
    }

    @Override
    public L fetchLookups() {
        return lookups.get();
    }

    @Override
    public MappingOutput transform(List<I> rows, L lookups, EtlContext ctx) {
        return transformation.apply(rows, lookups, ctx);
    }

    @Override
    public Map<String, Integer> load(MappingOutput output) {
        return loader.apply(output);
    }
}
