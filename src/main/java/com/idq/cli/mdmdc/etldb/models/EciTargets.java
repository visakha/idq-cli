package com.idq.cli.mdmdc.etldb.models;

import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.StagingRow;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Embedded;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the ECI `C_S_*` staging tables of MDM.
public final class EciTargets {

    private EciTargets() {}

    @Table("C_S_ECI_PTY")
    public record Party(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Party columns, BigDecimal birthWghtGrms, String prfrdLangCd,
            String srcPrfrdLangCd) implements StagingRow<Columns.Party> {}

    @Table("C_S_ECI_PTY_RLE")
    public record PartyRole(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.PartyRole columns) implements StagingRow<Columns.PartyRole> {}

    @Table("C_S_ECI_PTY_RLE_ADDR")
    public record Address(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Address columns) implements StagingRow<Columns.Address> {}

    @Table("C_S_ECI_PTY_RLE_ALT_ID")
    public record AlternateId(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.AlternateId columns) implements StagingRow<Columns.AlternateId> {}

    @Table("C_S_ECI_PTY_RLE_PHN")
    public record Phone(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Phone columns, String phnNumExt) implements StagingRow<Columns.Phone> {}

    @Table("C_S_ECI_PTY_RLE_EADDR")
    public record Email(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Email columns) implements StagingRow<Columns.Email> {}

    @Table("C_S_ECI_PTY_RLE_REL")
    public record Relationship(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Relationship columns) implements StagingRow<Columns.Relationship> {

        /// The embedded [Columns.Relationship] group is set column by column, as the table has it:
        /// `Relationship.builder().pkeySrcObject(key).audit(audit).ptyRleFk1(from).ptyRleFk2(to).relTp(type).build()`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String pkeySrcObject;
            private MdmAudit audit;
            private String ptyRleFk1;
            private String ptyRleFk2;
            private String relTypeCode;
            private String hierarchyCode;
            private String relTp;

            private Builder() {}

            public Builder pkeySrcObject(String value) { pkeySrcObject = value; return this; }
            public Builder audit(MdmAudit value) { audit = value; return this; }
            public Builder ptyRleFk1(String value) { ptyRleFk1 = value; return this; }
            public Builder ptyRleFk2(String value) { ptyRleFk2 = value; return this; }
            public Builder relTypeCode(String value) { relTypeCode = value; return this; }
            public Builder hierarchyCode(String value) { hierarchyCode = value; return this; }
            public Builder relTp(String value) { relTp = value; return this; }

            public Relationship build() {
                return new Relationship(pkeySrcObject, audit,
                        new Columns.Relationship(ptyRleFk1, ptyRleFk2, relTypeCode, hierarchyCode, relTp));
            }
        }
    }
}
