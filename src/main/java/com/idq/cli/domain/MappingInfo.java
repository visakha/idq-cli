package com.idq.cli.domain;

import java.util.List;
import org.springframework.data.relational.core.mapping.Table;

/// Identity of one IDQ mapping and the tables it reads and loads.
///
/// @param seq            workflow-wide documentation number, also the prefix of the markdown file
/// @param name           IDQ mapping name, e.g. `m_Tgt_C_S_TRS_Pty_OnGoing`
/// @param targets        `C_S_*` (and side) tables written, primary target first
/// @param sourceEntities `@Table` entities of the tables and views the mapping reads (its `IdqMapInitQuery` and
///                       lookups), e.g. [com.idq.cli.source.eci.EciSources.FamilyDelta]
public record MappingInfo(String seq, String name, SourceSystem source, List<String> targets,
        List<Class<?>> sourceEntities) {

    public static MappingInfo of(String seq, String name, SourceSystem source, List<String> targets,
            List<Class<?>> sourceEntities) {
        return new MappingInfo(seq, name, source, List.copyOf(targets), List.copyOf(sourceEntities));
    }

    public String doc() {
        return "docs/mappings/" + seq + "_" + name + ".md";
    }

    public String primaryTarget() {
        return targets.getFirst();
    }

    public List<String> sourceTables() {
        return sourceEntities.stream().map(MappingInfo::table).toList();
    }

    public static String table(Class<?> entity) {
        return entity.getAnnotation(Table.class).value();
    }
}
