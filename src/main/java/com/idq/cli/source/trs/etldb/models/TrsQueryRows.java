package com.idq.cli.source.trs.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/// Result rows of the TRS `IdqMapInitQuery`s and lookups. They are projections, not tables: each is returned
/// by a `@Query` method of the repository of the table it is read from (`source.trs.etldb.repo`).
public final class TrsQueryRows {

    private TrsQueryRows() {}

    /// [docs/mappings/001_m_Tgt_C_S_TRS_Pty_OnGoing.md#trs-001-valid-member-demographics]
    public record MemberDemographics(Long indvId, String firstName, String midName, String lastName, String sufxName,
            String prefixName, String genderCd, String raceCd, String ethnicityCd, String ssaValSw, String fileClSw,
            LocalDateTime dobDt, LocalDateTime createDt, String srcTbl, LocalDateTime deathDt) {}

    /// [docs/mappings/002_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md#trs-002-authorized-representative-flags]
    public record AuthorizedRepresentative(Long indvId, String arFlag, LocalDateTime effBeginDt, LocalDateTime effEndDt,
            LocalDateTime createDt) {}

    /// [docs/mappings/003_m_Tgt_C_S_TRS_Pty_Nm.md#trs-003-member-aliases]
    public record MemberAlias(Long indvId, String pkeyPty, String firstName, String midName, String lastName,
            String sufxName, String prefixName, LocalDateTime createDt, Long sequenceNum) {}

    /// [docs/mappings/004_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md#trs-004-member-ssn-and-ids]
    public record MemberIdentifiers(String ptyPkey, String memberId, LocalDateTime startDt, Long ssn, String cvInd) {}

    /// `lkp_Valid_SSN` of mapping 004: SSA-validated SSNs per individual.
    public record ValidSsn(Long indvId, Long ssn) {}

    /// [docs/mappings/005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md#trs-005-managed-care-plans]
    public record ManagedCarePlan(Long indvId, LocalDateTime beginDt, String mcPlan, Long historySeq,
            LocalDateTime endDt, LocalDateTime createDt) {}

    /// [docs/mappings/006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md#trs-006-case-phones-and-e-mail]
    public record CaseContact(Long indvId, Long caseNum, LocalDateTime createDt, String workPhNum, String otherPhNum,
            String email, String phNum, String officeNum, String workPhNumExt, String ptyPk) {}

    /// [docs/mappings/007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md#trs-007-member-switches]
    public record MemberSwitches(Long indvId, String fileClearanceSw, String ssaValidationSw, LocalDateTime effBeginDt,
            String twConvertInd, String ltcConvertInd, String ptyPk, LocalDateTime createDt, String srcTbl) {}

    /// [docs/mappings/008_m_Tgt_C_S_TRS_Pty_Rle_TOA.md#trs-008-type-of-assistance-segments]
    public record AssistanceSegment(String indvId, String typeOfAssistanceCd, LocalDateTime beginDt,
            LocalDateTime endDt, String srcTbl, String ptyPk, Long edgNum, Long caseNum, Long mciCreateSeq,
            String programCd, String partStatusCd, String systemCd, LocalDateTime convertDt, LocalDateTime createDt) {}

    /// [docs/mappings/009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md#trs-009-member-relationships]
    public record MemberRelationship(Long indvId, Long refIndvId, LocalDateTime effBeginDt, LocalDateTime effEndDt,
            String histNavInd, String relationshipTypeCd, String ptyPkey, String refPtyPkey, String ptyAltIdTp,
            LocalDateTime createDt, LocalDateTime updateDt) {}

    /// [docs/mappings/010_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md#trs-010-member-primary-care-providers]
    public record PrimaryCareProvider(Long indvId, Long historySeq, String mcProgCode, LocalDateTime beginDt,
            LocalDateTime createDt, String providerNum, LocalDateTime endDt, String ptyPk) {}

    /// `Lookup_C_B_PTY_RLE_ALT_ID` of mapping 010: provider TPI (`ALT_ID_TP 006`) to its newest active C21 source key.
    public record ProviderKey(String altIdVal, String pkeySrcObject) {}

    /// [docs/mappings/011_m_Tgt_C_S_TRS_Addr_1.md#trs-011-distinct-member-addresses]
    public record DistinctAddress(String addrId, String addrStNum, String addrStNumFrac, String addrStNm,
            String addrAptNum, String addrLine, String addrCity, String addrStateCd, String addrZip5, String addrZip4,
            String addrDwellingTypeCd, String addrStTypeCd, String addrStDirCd) {}

    /// [docs/mappings/012_m_Tgt_C_S_TRS_Addr_2.md#trs-012-member-address-assignments]
    public record AddressAssignment(Long indvId, Long caseNum, Long edgNum, String ptyPk, String addrTypeCd,
            LocalDateTime createDt, LocalDateTime effBeginDt, LocalDateTime effEndDt, String addrId,
            String addrLn1, String addrLn2, String bldngNm, String flrNum, String city, String county, String state,
            String cntryCd, String pstlCd, String pstlCdExt, BigDecimal lattd, BigDecimal lngtd, String vldtnMsg,
            String vldtnDesc, String mlbltyScr, String addrTpCd, String orgDesc, String orgDept, String orgNm,
            String bldgNmbr, String subBldgNm, String subBldgDesc, String geocdStsCd, String rsdntlDlvryInd,
            BigDecimal addrdrRsltPct, String erlyWrngCd, String cassErrCd, String dlvryPntVldn, String srcAddrLn1,
            String srcAddrLn2, String srcCity, String srcCounty, String srcState, String srcCntry, String srcPstlCd,
            String srcPstlCdExt) {}

    /// [docs/mappings/035_m_Tgt_C_S_TRS_Stg_TOA.md#trs-035-type-of-assistance-catalogue]
    public record AssistanceType(String programCode, String toaCode, String toaDesc, LocalDateTime effBeginDt,
            LocalDateTime effEndDt, LocalDateTime createDt, String updateUserId, LocalDateTime updateDt,
            BigDecimal uniqueTransId) {}
}
