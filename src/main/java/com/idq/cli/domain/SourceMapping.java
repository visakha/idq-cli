package com.idq.cli.domain;

import java.util.List;
import java.util.function.Supplier;

/// Base of the source-system mapping implementations: binds the mapping identity to its named queries so that
/// subclasses contain only the transformation.
///
/// ```java
/// class TrsPartyName extends SourceMapping<MemberAlias, NoLookups> implements MemberMapping.AlternateName<...> {
///     TrsPartyName(TrsQueries q) { super(INFO, q::fetchMemberAliases, NoLookups::none); }
/// }
/// ```
public abstract class SourceMapping<I, L> implements MemberMapping<I, L> {

    private final MappingInfo info;
    private final Supplier<List<I>> initQuery;
    private final Supplier<L> lookups;

    protected SourceMapping(MappingInfo info, Supplier<List<I>> initQuery, Supplier<L> lookups) {
        this.info = info;
        this.initQuery = initQuery;
        this.lookups = lookups;
    }

    @Override
    public MappingInfo info() {
        return info;
    }

    @Override
    public List<I> fetchIdqMapInitQueryResults() {
        return initQuery.get();
    }

    @Override
    public L fetchLookups() {
        return lookups.get();
    }
}
