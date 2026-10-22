package com.idq.cli.workflow;

import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceSystem;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/// All mapping implementations, ordered as their IDQ workflow executes them.
///
/// | source | order (documentation numbers)                                                     |
/// |--------|------------------------------------------------------------------------------------|
/// | TRS    | 001, 007, 002, 003, 004, 005, 006, 008, 009, 010, 011, 012, then 035 (TOA workflow)  |
/// | ECI    | 013 validation, 014 party, then 015-018                                            |
/// | FSS    | 019 validation, 020 party, then 021-024                                            |
/// | TTF    | 025 validation, 026 party, then 027-028                                            |
/// | WIC    | 029 validation, 030 party, then 031-033                                            |
/// | CRE    | 034 (one mapping loads every CRE target)                                           |
///
/// TRS 035 is the only mapping of the second TRS workflow, `wf_TRS_Stage_Load_TOA`, which the daily parent workflow
/// runs after `wf_TRS_Stage_Load_1_Ongoing`.
///
/// TRS runs the switches (007) before the authorized-representative flags (002) because 007 empties
/// `C_S_TRS_PTY_MNG_ATTR` and 002 only replaces its own attribute type.
@Component
public class MappingCatalog {

    static final List<String> TRS_ORDER = List.of("001", "007", "002", "003", "004", "005", "006", "008", "009",
            "010", "011", "012", "035");

    private final List<MemberMapping<?, ?>> mappings;

    public MappingCatalog(List<MemberMapping<?, ?>> mappings) {
        this.mappings = mappings.stream().sorted(Comparator.comparing(MappingCatalog::workflowPosition)).toList();
    }

    static String workflowPosition(MemberMapping<?, ?> m) {
        var seq = m.info().seq();
        int trs = TRS_ORDER.indexOf(seq);
        return m.info().source().ordinal() + ":" + (trs >= 0 ? "%03d".formatted(trs) : seq);
    }

    public List<MemberMapping<?, ?>> all() {
        return mappings;
    }

    public List<MemberMapping<?, ?>> of(SourceSystem source) {
        return mappings.stream().filter(m -> m.info().source() == source).toList();
    }

    public Optional<MemberMapping<?, ?>> byName(String name) {
        return mappings.stream().filter(m -> m.info().name().equalsIgnoreCase(name)).findFirst();
    }

    /// Mappings of a source that load the given target table.
    public List<MemberMapping<?, ?>> loading(SourceSystem source, String targetTable) {
        return of(source).stream().filter(m -> m.info().targetTables().stream().anyMatch(targetTable::equalsIgnoreCase))
                .toList();
    }

    /// `C_S_*` target tables of a source, in workflow order.
    public List<String> targetTables(SourceSystem source) {
        return of(source).stream().flatMap(m -> m.info().targetTables().stream()).filter(t -> t.startsWith("C_S_"))
                .distinct().toList();
    }

    public Map<SourceSystem, List<MemberMapping<?, ?>>> bySource() {
        return mappings.stream().collect(Collectors.groupingBy(m -> m.info().source(), java.util.TreeMap::new,
                Collectors.toList()));
    }
}
