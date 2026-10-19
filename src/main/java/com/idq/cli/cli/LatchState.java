package com.idq.cli.cli;

import com.idq.cli.domain.Domain;
import com.idq.cli.domain.SourceSystem;
import java.util.EnumSet;
import java.util.Optional;
import java.util.Set;
import org.springframework.stereotype.Component;

/// The working context shared by the shell and the REST API: one source system, one target table, one mapping
/// (each requiring the previous one) and one or more domains.
@Component
public class LatchState {

    private SourceSystem source;
    private String targetTable;
    private String mapping;
    private final Set<Domain> domains = EnumSet.of(Domain.MEMBER);

    public synchronized Optional<SourceSystem> source() {
        return Optional.ofNullable(source);
    }

    public synchronized Optional<String> targetTable() {
        return Optional.ofNullable(targetTable);
    }

    public synchronized Optional<String> mapping() {
        return Optional.ofNullable(mapping);
    }

    public synchronized Set<Domain> domains() {
        return Set.copyOf(domains);
    }

    /// Latching another source system clears the target table and mapping of the previous one.
    public synchronized void latchSource(SourceSystem value) {
        if (value != source) {
            targetTable = null;
            mapping = null;
        }
        source = value;
    }

    public synchronized void unlatchSource() {
        source = null;
        targetTable = null;
        mapping = null;
    }

    public synchronized void latchTargetTable(String table) {
        if (!table.equals(targetTable)) {
            mapping = null;
        }
        targetTable = table;
    }

    public synchronized void unlatchTargetTable() {
        targetTable = null;
        mapping = null;
    }

    public synchronized void latchMapping(String value) {
        mapping = value;
    }

    public synchronized void unlatchMapping() {
        mapping = null;
    }

    public synchronized void latchDomain(Domain domain) {
        domains.add(domain);
    }

    public synchronized void unlatchDomain(Domain domain) {
        domains.remove(domain);
    }

    /// `TRS+C_S_TRS_PTY+m_Tgt_C_S_TRS_Pty_OnGoing`, or empty when nothing is latched.
    public synchronized String context() {
        var parts = new java.util.ArrayList<String>();
        if (source != null) {
            parts.add(source.name());
        }
        if (targetTable != null) {
            parts.add(targetTable);
        }
        if (mapping != null) {
            parts.add(mapping);
        }
        return String.join("+", parts);
    }
}
