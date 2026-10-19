package com.idq.cli.domain;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.MappingOutput;
import java.util.List;

/// Contract of one Member-domain mapping: read the rows of its `IdqMapInitQuery`, transform them exactly as the IDQ
/// mapping does, and describe what to load. Transformation is a pure function so it can be unit tested without a
/// database.
///
/// The sub-domain interfaces below fix [#subDomain()]; implementations live in the source-system packages.
///
/// @param <I> row type of the `IdqMapInitQuery`
/// @param <L> cached lookup tables specific to the mapping (IDQ lookup transformations), [NoLookups] when none
public interface MemberMapping<I, L> {

    MappingInfo info();

    SubDomain subDomain();

    /// Runs the `IdqMapInitQuery` (first SQL of the mapping) through its Spring Data JDBC named-query interface.
    List<I> fetchIdqMapInitQueryResults();

    /// Loads the mapping-specific lookup caches.
    L fetchLookups();

    MappingOutput transform(List<I> rows, L lookups, EtlContext ctx);

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

    interface Demographics<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.DEMOGRAPHICS;
        }
    }

    interface PhoneEmail<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.PHONE_EMAIL;
        }
    }

    interface Address<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.ADDRESS;
        }
    }

    interface AlternateId<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.ALTERNATE_ID;
        }
    }

    interface AlternateName<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.ALTERNATE_NAME;
        }
    }

    interface ManagedAttribute<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.PARTY_MANAGED_ATTRIB;
        }
    }

    interface Role<I, L> extends MemberMapping<I, L> {
        @Override
        default SubDomain subDomain() {
            return SubDomain.ROLE;
        }
    }
}
