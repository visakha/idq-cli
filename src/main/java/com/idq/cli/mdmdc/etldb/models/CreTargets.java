package com.idq.cli.mdmdc.etldb.models;

import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.StagingRow;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Embedded;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the CRE `C_S_*` staging tables of MDM.
///
/// The CRE tables differ from the other sources: `C_S_CRE_PTY` has no `FLAG_SRC`, `C_S_CRE_PTY_RLE_ALT_ID` no `CV_IND`
/// and `C_S_CRE_PTY_RLE_ADDR` a usage type but no effective dates, hence their own column groups.
public final class CreTargets {

    private CreTargets() {}

    @Table("C_S_CRE_PTY")
    public record Party(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.PartyWithoutFlag columns) implements StagingRow<Columns.PartyWithoutFlag> {}

    @Table("C_S_CRE_PTY_RLE")
    public record PartyRole(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.PartyRole columns) implements StagingRow<Columns.PartyRole> {}

    @Table("C_S_CRE_PTY_RLE_ADDR")
    public record Address(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.AddressWithUsage columns) implements StagingRow<Columns.AddressWithUsage> {}

    @Table("C_S_CRE_PTY_RLE_ALT_ID")
    public record AlternateId(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.AlternateIdWithoutCvInd columns)
            implements StagingRow<Columns.AlternateIdWithoutCvInd> {}

    @Table("C_S_CRE_PTY_RLE_PHN")
    public record Phone(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Phone columns) implements StagingRow<Columns.Phone> {}
}
