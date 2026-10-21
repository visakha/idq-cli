package com.idq.cli.domain;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.MappingOutput;
import java.util.List;
import java.util.Map;
import org.springframework.core.ResolvableType;

/// Contract of one Member-domain mapping: read the rows of its `IdqMapInitQuery`, transform them exactly as the IDQ
/// mapping does, and describe what to load. Transformation is a pure function so it can be unit tested without a
/// database.
///
/// Every mapping is a plain `source.<src>.etlmap.svc` service handed to the workflow runner as a
/// [com.idq.cli.core.ServiceMapping].
///
/// @param <I> row type of the `IdqMapInitQuery`
/// @param <L> cached lookup tables specific to the mapping (IDQ lookup transformations), [NoLookups] when none
public interface MemberMapping<I, L> {

    MappingInfo info();

    SubDomain subDomain();

    /// Runs the `IdqMapInitQuery` (first SQL of the mapping) through its Spring Data JDBC repository.
    List<I> fetchIdqMapInitQueryResults();

    /// Loads the mapping-specific lookup caches.
    L fetchLookups();

    MappingOutput transform(List<I> rows, L lookups, EtlContext ctx);

    /// Writes the output through the mapping's repositories.
    ///
    /// @return rows inserted (or deleted) per table, in load order
    Map<String, Integer> load(MappingOutput output);

    /// Record type of the `IdqMapInitQuery` rows, for the audit reports.
    default Class<?> rowType() {
        return ResolvableType.forClass(getClass()).as(MemberMapping.class).resolveGeneric(0);
    }

    default Domain domain() {
        return Domain.MEMBER;
    }

    /// Lookup placeholder for mappings without source-specific lookups.
    record NoLookups() {
        public static final NoLookups NONE = new NoLookups();

        public static NoLookups none() {
            return NONE;
        }
    }
}
