package com.idq.cli.mdmdc.etldb.models;

import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.StagingRow;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Embedded;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the TRS `C_S_*` staging tables of MDM: common columns ([MdmAudit]) plus one [Columns] group each.
public final class TrsTargets {

    private TrsTargets() {}

    @Table("C_S_TRS_PTY")
    public record Party(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Party columns, LocalDateTime deathDt) implements StagingRow<Columns.Party> {}

    @Table("C_S_TRS_PTY_RLE")
    public record PartyRole(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.PartyRole columns) implements StagingRow<Columns.PartyRole> {}

    @Table("C_S_TRS_PTY_NM")
    public record PartyName(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.PartyName columns) implements StagingRow<Columns.PartyName> {}

    @Table("C_S_TRS_PTY_MNG_ATTR")
    public record ManagedAttribute(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.ManagedAttribute columns) implements StagingRow<Columns.ManagedAttribute> {}

    @Table("C_S_TRS_PTY_RLE_ALT_ID")
    public record AlternateId(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.AlternateId columns) implements StagingRow<Columns.AlternateId> {}

    @Table("C_S_TRS_PTY_RLE_PLN")
    public record Plan(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Plan columns) implements StagingRow<Columns.Plan> {}

    @Table("C_S_TRS_PTY_RLE_PHN")
    public record Phone(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Phone columns) implements StagingRow<Columns.Phone> {}

    @Table("C_S_TRS_PTY_RLE_EADDR")
    public record Email(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Email columns) implements StagingRow<Columns.Email> {}

    @Table("C_S_TRS_PTY_RLE_TOA")
    public record TypeOfAssistance(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.TypeOfAssistance columns) implements StagingRow<Columns.TypeOfAssistance> {}

    /// `C_S_LU_TOA` - the TIERS type-of-assistance catalogue (`m_Tgt_C_S_TRS_Stg_TOA`). An MDM lookup table: it has
    /// no `SRC_LAST_UPD_DT`, so it carries its own audit columns instead of [MdmAudit].
    @Table("C_S_LU_TOA")
    public record TypeOfAssistanceCatalogue(@Id String pkeySrcObject, LocalDateTime lastUpdateDate,
            LocalDateTime createDate, String creator, String updatedBy, String srcRowid, Integer hubStateInd,
            String toaCd, String toaLbl, String toaDesc, String mbrPrgCd, LocalDateTime effStrtDt,
            LocalDateTime effEndDt) {}

    @Table("C_S_TRS_PTY_RLE_REL")
    public record Relationship(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Relationship columns) implements StagingRow<Columns.Relationship> {}

    @Table("C_S_TRS_PTY_RLE_REL_PROV")
    public record ProviderRelationship(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Relationship columns) implements StagingRow<Columns.Relationship> {}

    @Table("C_S_TRS_PTY_RLE_ADDR")
    public record Address(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Address columns) implements StagingRow<Columns.Address> {}
}
