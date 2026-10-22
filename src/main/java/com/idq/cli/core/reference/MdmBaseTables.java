package com.idq.cli.core.reference;

import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// MDM base-object tables that some mappings look up (hub state, provider TPI, merge history). The `@Id`s are
/// provisional.
public final class MdmBaseTables {

    private MdmBaseTables() {}

    /// Provisional `@Id` `ROWID_XREF`: the table has no primary key, Spring Data JDBC needs one.
    @Table("C_B_PTY_XREF")
    public record PartyXref(@Id Long rowidXref, String pkeySrcObject, String rowidObject, String rowidSystem,
            Long hubStateInd) {}

    /// Provisional `@Id` `ROWID_OBJECT`: the table has no primary key, Spring Data JDBC needs one.
    @Table("C_B_PTY_RLE_ALT_ID")
    public record PartyRoleAltId(@Id String rowidObject, String altIdTp, String altIdVal) {

        /// `PartyRoleAltId.builder().rowidObject(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String rowidObject;
            private String altIdTp;
            private String altIdVal;

            private Builder() {}

            public Builder rowidObject(String value) { rowidObject = value; return this; }
            public Builder altIdTp(String value) { altIdTp = value; return this; }
            public Builder altIdVal(String value) { altIdVal = value; return this; }

            public PartyRoleAltId build() {
                return new PartyRoleAltId(rowidObject, altIdTp, altIdVal);
            }
        }
    }

    /// Provisional `@Id` `PKEY_SRC_OBJECT`: the table has no primary key, Spring Data JDBC needs one.
    @Table("C_B_PTY_RLE_ALT_ID_XREF")
    public record PartyRoleAltIdXref(String rowidObject, @Id String pkeySrcObject, LocalDateTime srcLastUpdDt,
            String rowidSystem, Integer hubStateInd) {

        /// `PartyRoleAltIdXref.builder().rowidObject(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String rowidObject;
            private String pkeySrcObject;
            private LocalDateTime srcLastUpdDt;
            private String rowidSystem;
            private Integer hubStateInd;

            private Builder() {}

            public Builder rowidObject(String value) { rowidObject = value; return this; }
            public Builder pkeySrcObject(String value) { pkeySrcObject = value; return this; }
            public Builder srcLastUpdDt(LocalDateTime value) { srcLastUpdDt = value; return this; }
            public Builder rowidSystem(String value) { rowidSystem = value; return this; }
            public Builder hubStateInd(Integer value) { hubStateInd = value; return this; }

            public PartyRoleAltIdXref build() {
                return new PartyRoleAltIdXref(rowidObject, pkeySrcObject, srcLastUpdDt, rowidSystem, hubStateInd);
            }
        }
    }

    /// Provisional `@Id` `SRC_ROWID_OBJECT`: the table has no primary key, Spring Data JDBC needs one. Only the columns
    /// the CRE merge lookups read (`LKP_HMRG_*`) are modelled.
    @Table("C_B_PTY_HMRG")
    public record PartyHmrg(@Id String srcRowidObject, String tgtRowidObject) {}
}
