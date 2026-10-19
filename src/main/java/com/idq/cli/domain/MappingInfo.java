package com.idq.cli.domain;

import java.util.List;

/// Identity of one IDQ mapping and the tables it reads and loads.
///
/// @param seq          workflow-wide documentation number, also the prefix of the markdown file
/// @param name         IDQ mapping name, e.g. `m_Tgt_C_S_TRS_Pty_OnGoing`
/// @param targets      `C_S_*` (and side) tables written, primary target first
/// @param sourceTables tables read by the `IdqMapInitQuery`
public record MappingInfo(String seq, String name, SourceSystem source, List<String> targets,
        List<String> sourceTables) {

    public static MappingInfo of(String seq, String name, SourceSystem source, List<String> targets,
            List<String> sourceTables) {
        return new MappingInfo(seq, name, source, List.copyOf(targets), List.copyOf(sourceTables));
    }

    public String doc() {
        return "docs/mappings/" + seq + "_" + name + ".md";
    }

    public String primaryTarget() {
        return targets.getFirst();
    }
}
