package com.idq.cli.source.trs;

import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.StagingRow;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Embedded;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the TRS target tables: common columns ([MdmAudit]) plus one [Columns] group each.
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

    @Table("C_S_TRS_PTY_RLE_REL")
    public record Relationship(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Relationship columns) implements StagingRow<Columns.Relationship> {}

    @Table("C_S_TRS_PTY_RLE_REL_PROV")
    public record ProviderRelationship(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Relationship columns) implements StagingRow<Columns.Relationship> {}

    @Table("C_S_TRS_PTY_RLE_ADDR")
    public record Address(@Id String pkeySrcObject, @Embedded.Empty MdmAudit audit,
            @Embedded.Empty Columns.Address columns) implements StagingRow<Columns.Address> {}

    /// `STG_TRS_VALID_MEMBERS`: registry of member source keys accepted by `m_Tgt_C_S_TRS_Pty_OnGoing`; every other
    /// TRS mapping joins to it.
    @Table("STG_TRS_VALID_MEMBERS")
    public record ValidMember(Long indvId, @Id String ptyPk, String srcTbl, LocalDateTime createDate) {}

    /// `STG_TRS_D_UNQ_ADDR`: each distinct TIERS address validated once by `m_Tgt_C_S_TRS_Addr_1`.
    @Table("STG_TRS_D_UNQ_ADDR")
    public record UniqueAddressDelta(
            @Id String addrId,
            @Column("ADDR_LN_1") String addrLn1, @Column("ADDR_LN_2") String addrLn2, String bldngNm,
            String flrNum, String city, String county, String state, String cntryCd, String pstlCd,
            String pstlCdExt, BigDecimal lattd, BigDecimal lngtd, String vldtnMsg, String vldtnDesc,
            String mlbltyScr, String addrTpCd, String orgDesc, String orgDept, String orgNm, String bldgNmbr,
            String subBldgNm, String subBldgDesc, String geocdStsCd, String rsdntlDlvryInd,
            BigDecimal addrdrRsltPct, String erlyWrngCd, String cassErrCd, String dlvryPntVldn,
            @Column("SRC_ADDR_LN_1") String srcAddrLn1, @Column("SRC_ADDR_LN_2") String srcAddrLn2,
            String srcCity, String srcCounty, String srcState, String srcCntry, String srcPstlCd,
            String srcPstlCdExt) {}
}
