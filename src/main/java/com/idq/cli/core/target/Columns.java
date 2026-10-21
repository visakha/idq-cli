package com.idq.cli.core.target;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Embedded;

/// Sub-domain column groups shared by the `C_S_<SRC>_*` tables of every source system.
///
/// A source-specific entity (for example `C_S_TRS_PTY`) embeds [MdmAudit] plus exactly one of these groups, so the
/// transformation code is written once per sub-domain and reused by all sources through generics.
public sealed interface Columns {

    /// `C_S_*_PTY` - demographics.
    record Party(
            String ptyBoClassCd, String prfxNm, String frstNm, String mdlNm, String lstNm, String sfxNm,
            String fullNm, String gndrCd, LocalDateTime birthDt, String flagSrc, String srcFullNm,
            String ethncty, String srcEthncty, String raceCd, String srcRaceCd) implements Columns {}

    /// `C_S_*_PTY` of the sources whose table has no `FLAG_SRC` column (CRE).
    record PartyWithoutFlag(
            String ptyBoClassCd, String prfxNm, String frstNm, String mdlNm, String lstNm, String sfxNm,
            String fullNm, String gndrCd, LocalDateTime birthDt, String srcFullNm, String ethncty,
            String srcEthncty, String raceCd, String srcRaceCd) implements Columns {}

    /// `C_S_*_PTY_RLE` - the member role of a party.
    record PartyRole(String ptyFk, String rleBoClassCd) implements Columns {}

    /// `C_S_*_PTY_NM` - alternate names.
    record PartyName(
            String ptyFk, String nmTp, String frstNm, String mdlNm, String lstNm, String pfxNm, String fullNm,
            String sfxNm, String srcFullNm) implements Columns {}

    /// `C_S_*_PTY_MNG_ATTR` - party managed attributes (switches and flags).
    record ManagedAttribute(String ptyFk, String mngAttrTp, String mngAttrVal) implements Columns {}

    /// `C_S_*_PTY_RLE_ALT_ID` - alternate identifiers.
    record AlternateId(
            String ptyRleFk, String altIdTp, String altIdVal, String stsCd, String altIdTpFltr, String cvInd)
            implements Columns {}

    /// `C_S_*_PTY_RLE_ALT_ID` of the sources whose table has no `CV_IND` column (CRE).
    record AlternateIdWithoutCvInd(String ptyRleFk, String altIdTp, String altIdVal, String stsCd, String altIdTpFltr)
            implements Columns {}

    /// `C_S_*_PTY_RLE_PHN` - phone numbers.
    record Phone(String ptyRleFk, String phnTp, String usgTp, String phnNum, String prefLvl) implements Columns {}

    /// `C_S_*_PTY_RLE_EADDR` - electronic (e-mail) addresses.
    record Email(String ptyRleFk, String addrTp, String usgTp, String elecAddr, String stsCd, String isVld)
            implements Columns {}

    /// `C_S_*_PTY_RLE_ADDR` - postal addresses.
    record Address(
            String ptyRleFk, String addrTp, String prefLvl, String hierarchyCode, String hmRelTpCd, String locIdn,
            @Embedded.Empty ValidatedAddress validated,
            @Embedded.Empty SourceAddress source,
            LocalDateTime effStrtDt, LocalDateTime effEndDt) implements Columns {}

    /// `C_S_*_PTY_RLE_ADDR` of the sources whose table has a usage type but no effective dates (CRE).
    record AddressWithUsage(
            String ptyRleFk, String addrTp, String usgTp, String prefLvl, String hierarchyCode, String hmRelTpCd,
            String locIdn,
            @Embedded.Empty ValidatedAddress validated,
            @Embedded.Empty SourceAddress source) implements Columns {}

    /// `C_S_*_PTY_RLE_REL` / `_REL_PROV` - relationships between two party roles.
    record Relationship(
            @Column("PTY_RLE_FK_1") String ptyRleFk1,
            @Column("PTY_RLE_FK_2") String ptyRleFk2,
            String relTypeCode, String hierarchyCode, String relTp) implements Columns {}

    /// `C_S_*_PTY_RLE_PLN` - managed care plan enrolment.
    record Plan(String ptyRleFk, String plnFk) implements Columns {}

    /// `C_S_*_PTY_RLE_TOA` - type of assistance.
    record TypeOfAssistance(
            String toaSource, String toaFk, LocalDateTime effStrtDt, LocalDateTime effEndDt, String ptyRleFk,
            String prtcpntStsCd, String indvId, String caseNum, String edgNum, String sgmntKey, String cnvrtSysCd,
            LocalDateTime cnvrtDt) implements Columns {}

    /// Address attributes as returned by address validation.
    record ValidatedAddress(
            @Column("ADDR_LN_1") String addrLn1, @Column("ADDR_LN_2") String addrLn2, String bldngNm, String flrNum,
            String city, String county, String state, String cntryCd, String pstlCd, String pstlCdExt,
            BigDecimal lattd, BigDecimal lngtd, String vldtnMsg, String mlbltyScr, String addrTpCd,
            String orgDesc, String orgNm, String bldgNmbr, String subBldgNm,
            String subBldgDesc, String geocdStsCd, String rsdntlDlvryInd) {}

    /// Address attributes exactly as the source system reported them.
    record SourceAddress(
            @Column("SRC_ADDR_LN_1") String srcAddrLn1, @Column("SRC_ADDR_LN_2") String srcAddrLn2, String srcCity,
            String srcCounty, String srcState, String srcCntry, String srcPstlCd, String srcPstlCdExt) {}
}
