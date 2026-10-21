package com.idq.cli.mdmdc.etldb.models;

import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.StagingRow;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Embedded;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the FSS `C_S_*` staging tables of MDM.
public final class FssTargets {

    private FssTargets() {}

    @Table("C_S_FSS_PTY")
    public record Party(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Party columns, String prfrdLangCd) implements StagingRow<Columns.Party> {}

    @Table("C_S_FSS_PTY_RLE")
    public record PartyRole(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.PartyRole columns) implements StagingRow<Columns.PartyRole> {}

    @Table("C_S_FSS_PTY_RLE_ADDR")
    public record Address(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Address columns) implements StagingRow<Columns.Address> {}

    @Table("C_S_FSS_PTY_RLE_ALT_ID")
    public record AlternateId(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.AlternateId columns) implements StagingRow<Columns.AlternateId> {}

    @Table("C_S_FSS_PTY_RLE_PHN")
    public record Phone(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Phone columns, String phnNumExt) implements StagingRow<Columns.Phone> {}

    @Table("C_S_FSS_PTY_RLE_EADDR")
    public record Email(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Email columns) implements StagingRow<Columns.Email> {}

    @Table("C_S_FSS_PTY_RLE_REL")
    public record Relationship(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Relationship columns) implements StagingRow<Columns.Relationship> {}
}
