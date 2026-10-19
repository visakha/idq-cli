package com.idq.cli.core.reference;

import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// MDM base-object tables that some mappings look up (hub state, provider TPI). The `@Id`s are provisional.
public final class MdmBaseTables {

    private MdmBaseTables() {}

    /// Provisional `@Id` `ROWID_XREF`: the table has no primary key, Spring Data JDBC needs one.
    @Table("C_B_PTY_XREF")
    public record PartyXref(@Id Long rowidXref, String pkeySrcObject, String rowidObject, String rowidSystem,
            Long hubStateInd) {}

    /// Provisional `@Id` `ROWID_OBJECT`: the table has no primary key, Spring Data JDBC needs one.
    @Table("C_B_PTY_RLE_ALT_ID")
    public record PartyRoleAltId(@Id String rowidObject, String altIdTp, String altIdVal) {}

    /// Provisional `@Id` `PKEY_SRC_OBJECT`: the table has no primary key, Spring Data JDBC needs one.
    @Table("C_B_PTY_RLE_ALT_ID_XREF")
    public record PartyRoleAltIdXref(String rowidObject, @Id String pkeySrcObject, LocalDateTime srcLastUpdDt,
            String rowidSystem, Integer hubStateInd) {}
}
