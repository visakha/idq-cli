package com.idq.cli.core.reference;

import java.time.LocalDateTime;
import org.springframework.data.relational.core.mapping.Table;

/// MDM base-object tables that some mappings look up (hub state, provider TPI); read-only, no `@Id`.
public final class MdmBaseTables {

    private MdmBaseTables() {}

    @Table("C_B_PTY_XREF")
    public record PartyXref(Long rowidXref, String pkeySrcObject, String rowidObject, String rowidSystem,
            Long hubStateInd) {}

    @Table("C_B_PTY_RLE_ALT_ID")
    public record PartyRoleAltId(String rowidObject, String altIdTp, String altIdVal) {}

    @Table("C_B_PTY_RLE_ALT_ID_XREF")
    public record PartyRoleAltIdXref(String rowidObject, String pkeySrcObject, LocalDateTime srcLastUpdDt,
            String rowidSystem, Integer hubStateInd) {}
}
