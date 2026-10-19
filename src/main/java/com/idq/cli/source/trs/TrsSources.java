package com.idq.cli.source.trs;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the TRS source tables and views read by
/// `wf_TRS_Stage_Load_1_Ongoing`.
///
/// The mappings read through their `IdqMapInitQuery` records in [TrsQueries]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_TRS`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// `STG_TRS_VALID_MEMBERS` and `STG_TRS_D_UNQ_ADDR` are loaded by mappings 001 and 011 before later mappings
/// read them, so their entities are [TrsTargets.ValidMember] and [TrsTargets.UniqueAddress].
public final class TrsSources {

    private TrsSources() {}

    /// Provisional `@Id` `REF_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_CD_REF")
    public record CdRef(@Id Long refId, String tablename, String code, String description) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_CV_ED_MCI_EDG_INDV")
    public record CvEdMciEdgIndv(@Id BigDecimal indvId, String programCd, BigDecimal edgNum, BigDecimal mciCreateSeq,
            BigDecimal historySeq, BigDecimal caseNum, String partStatusCd, String typeOfAssistanceCd,
            String createUserId, LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt,
            String systemCd, String conversionInd, LocalDateTime eligEffBeginDt, LocalDateTime eligEffEndDt,
            LocalDateTime convertDt, String refugeeInd, String medInd, String saverrMergeId, String processId,
            BigDecimal realIndvId, String processTypeCd, LocalDateTime stgLastUpdateDate) {}

    /// Provisional `@Id` `CASE_NUM`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_DC_CASES")
    public record DcCases(@Id BigDecimal caseNum, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, String languageCd, LocalDateTime caseClosedDt, String caseStatusCd,
            String caseModeCd, String reactivationInd, LocalDateTime reactivationDt, LocalDateTime interviewDt,
            String authrepFirstName, String authrepLastName, String authrepMidName, String authrepPrefixName,
            String authrepPhNum, String authrepOrgName, String workPhNum, String otherPhNum, String email,
            LocalDateTime appRecvdDt, String phNum, BigDecimal officeNum, String authrepIndvIdVrfCd, String authRepSw,
            LocalDateTime archiveDt, String interviewTypeCd, String dhsEmpCaseSw, String authorizedEmailSw,
            String authrepSufxName, String unableToLocateSw, BigDecimal workPhNumExt, LocalDateTime actionDt,
            String authrepWorkNum, String authrepOtherNum, String relationshipIndvCd, String authrepCaregiverSw,
            String processId, BigDecimal empId, String whpPhNum, String deleteSw, String applicationSignedSw,
            String mdAllowedSw, String mdExistsSw, String vendorStaffSw, String otherLanguage,
            BigDecimal disasterSeqNum, String spProgReqTypeCd, String appIntakeInd, String cboSw, String mbccSw,
            String navigatorSw, String everyoneLiveAtHouseholdSw, String renewalCvgFutureYrsCd, String authRepId,
            String interpreterLangCd, String sentAuthrepSw, String authrepTypeCd, String authrepVerfCd,
            LocalDateTime bprComntsRefreshDt, LocalDateTime stgLastUpdateDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_DC_CASE_INDV")
    public record DcCaseIndv(@Id BigDecimal indvId, BigDecimal caseNum, BigDecimal historySeq, String activeInCaseSw,
            String createUserId, String updateUserId, LocalDateTime createDt, LocalDateTime updateDt,
            BigDecimal uniqueTransId, LocalDateTime effBeginDt, LocalDateTime effEndDt, String histNavInd,
            String headOfHouseholdSw, String employeeSw, LocalDateTime archiveDt, String inactiveReasonCds,
            String reactiveDeceasedMaReqSw, String isPermissionReqdSw, String eldsPermissionProvSw,
            LocalDateTime stgLastUpdateDate) {}

    /// Provisional `@Id` `CASE_NUM`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_DC_PRIMARY_PAYEE")
    public record DcPrimaryPayee(@Id BigDecimal caseNum, BigDecimal edgNum, BigDecimal historySeq, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, String typeOfAssistanceCd, String issuanceMethodCd,
            String addrDiffFromCaseSw, String addrStNum, String addrStNumFrac, String addrStNm, String addrAptNum,
            String addrLine, String addrCity, String addrZip5, String addrZip4, String addrDwellingTypeCd,
            LocalDateTime payeeBeginDt, LocalDateTime payeeEndDt, LocalDateTime archiveDt, BigDecimal indvId,
            String altPayeeExistsSw, String addrStDirCd, String addrStTypeCd, String addrCountyCd, String addrStateCd,
            String ebtSw, String freezeAddressUpdateSw, String collectPhysicalAddrSw, BigDecimal sequenceNum,
            String addrTypeCd, LocalDateTime stgLastUpdateDate, String addrTypeCdNotNull) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_DEACTIVED_MEMBERS")
    public record DeactivedMembers(@Id BigDecimal indvId, String ptyPk, String srcTbl, LocalDateTime createDate,
            LocalDateTime srcDeactivationDate, LocalDateTime loadDate, String inactiveInd, String deleteSw,
            String processedYn) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_DC_MCI_ALIAS")
    public record DCvDcMciAlias(@Id BigDecimal indvId, BigDecimal sequenceNum, BigDecimal historySeq, String firstName,
            String midName, String lastName, String sufxName, String prefixName, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt, String saverrMessageId) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_DC_MCI_INDV")
    public record DCvDcMciIndv(@Id BigDecimal indvId, BigDecimal historySeq, String firstName, String midName,
            String lastName, String sufxName, String prefixName, BigDecimal ssn, String genderCd, LocalDateTime dobDt,
            String raceCd, String ethnicityCd, LocalDateTime otTanfDt, BigDecimal fipsCntyCd, LocalDateTime twConvertDt,
            LocalDateTime ltcConvertDt, String createSystemCd, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, String twConvertInd, LocalDateTime archiveDt, String ltcConvertInd,
            String inactiveInd, String saverrMessageId, LocalDateTime fsConvertDt, LocalDateTime maConvertDt,
            LocalDateTime meConvertDt, LocalDateTime ccConvertDt, LocalDateTime mcConvertDt, LocalDateTime tfConvertDt,
            String inactivateTypeCd, String potentialDuplicateSw, String potentialDuplicateTypeCd,
            LocalDateTime inactivatedDt, String inactivatedByUserId, LocalDateTime potentialDuplicateDt,
            String potentialDuplicateUserId, BigDecimal potentialDupPrimaryId, LocalDateTime chConvertDt) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_DC_MRG_SPRT_INDV")
    public record DCvDcMrgSprtIndv(@Id BigDecimal indvId, BigDecimal oldIndvId, BigDecimal sequenceNum, String typeCd,
            BigDecimal historySeq, LocalDateTime mergeSeparateDt, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, String saverrMessageId, String primaryIndvSw, LocalDateTime archiveDt) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_ED_MCI_EDG_INDV")
    public record DCvEdMciEdgIndv(@Id BigDecimal indvId, String programCd, BigDecimal edgNum, BigDecimal mciCreateSeq,
            BigDecimal historySeq, BigDecimal caseNum, String partStatusCd, String typeOfAssistanceCd,
            String createUserId, LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt,
            String systemCd, String conversionInd, LocalDateTime eligEffBeginDt, LocalDateTime eligEffEndDt,
            LocalDateTime convertDt, String refugeeInd, String medInd, String saverrMergeId, String processId,
            BigDecimal realIndvId, String processTypeCd, LocalDateTime loadDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_MCI_EDG_INDV_TOA")
    public record DCvMciEdgIndvToa(@Id BigDecimal indvId, String programCd, BigDecimal edgNum, BigDecimal mciCreateSeq,
            BigDecimal historySeq, BigDecimal caseNum, String partStatusCd, String typeOfAssistanceCd,
            String createUserId, LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt,
            String systemCd, String conversionInd, LocalDateTime eligEffBeginDt, LocalDateTime eligEffEndDt,
            LocalDateTime convertDt, String refugeeInd, String medInd, String saverrMergeId, String processId,
            BigDecimal realIndvId, String processTypeCd, LocalDateTime loadDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_ALIAS")
    public record DDcAlias(@Id BigDecimal indvId, BigDecimal seqNum, BigDecimal historySeq, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, String lastName, String firstName, String sufxName,
            String prefixName, String midName, BigDecimal aliasIndvId, LocalDateTime archiveDt, String isCompleteSw,
            LocalDateTime loadDate) {}

    /// Provisional `@Id` `CASE_NUM`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_CASES")
    public record DDcCases(@Id BigDecimal caseNum, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, String languageCd, LocalDateTime caseClosedDt, String caseStatusCd,
            String caseModeCd, String reactivationInd, LocalDateTime reactivationDt, LocalDateTime interviewDt,
            String authrepFirstName, String authrepLastName, String authrepMidName, String authrepPrefixName,
            String authrepPhNum, String authrepOrgName, String workPhNum, String otherPhNum, String email,
            LocalDateTime appRecvdDt, String phNum, BigDecimal officeNum, String authrepIndvIdVrfCd, String authRepSw,
            LocalDateTime archiveDt, String interviewTypeCd, String dhsEmpCaseSw, String authorizedEmailSw,
            String authrepSufxName, String unableToLocateSw, BigDecimal workPhNumExt, LocalDateTime actionDt,
            String authrepWorkNum, String authrepOtherNum, String relationshipIndvCd, String authrepCaregiverSw,
            String processId, BigDecimal empId, String whpPhNum, String deleteSw, String applicationSignedSw,
            String mdAllowedSw, String mdExistsSw, String vendorStaffSw, String otherLanguage,
            BigDecimal disasterSeqNum, String spProgReqTypeCd, String appIntakeInd, String cboSw, String mbccSw,
            String navigatorSw, String everyoneLiveAtHouseholdSw, String renewalCvgFutureYrsCd, String authRepId,
            String interpreterLangCd, String sentAuthrepSw, String authrepTypeCd, String authrepVerfCd,
            LocalDateTime bprComntsRefreshDt, LocalDateTime loadDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_INDV")
    public record DDcIndv(@Id BigDecimal indvId, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, BigDecimal ssn, LocalDateTime dobDt, String lastName, String firstName,
            String sufxName, String prefixName, String midName, String dobVrfCd, String raceCd, String ssaValidationSw,
            String ssnVrfCd, String ethnicityCd, String genderCd, String inactiveInd, BigDecimal empId,
            String fileClearanceSw, BigDecimal chipSeqNum, String mergeSeparateInd, LocalDateTime deathDt,
            String deceasedDtVrfCd, String highneedProfileSw, String highneedCriteriaCd, String mhmrCaseNum,
            LocalDateTime archiveDt, String deleteSw, String fedRcgnzdIndianTribeSw, String splHealthCareEnrolledSw,
            @Column("IN_FC_ON_18TH_BIRTHDAY_SW") String inFcOn18thBirthdaySw,
            @Column("IN_FC_ON_18TH_BRTHDAT_VRF_CD") String inFcOn18thBrthdatVrfCd, String stateCd,
            BigDecimal dfpsPersonId, String maidenName, String mothersMaidenName, String isCompleteSw, String otherRace,
            String inactivateTypeCd, String potentialDuplicateSw, String potentialDuplicateTypeCd,
            LocalDateTime inactivatedDt, String inactivatedByUserId, LocalDateTime potentialDuplicateDt,
            String potentialDuplicateUserId, BigDecimal potentialDupPrimaryId, BigDecimal mergeRequestSeqNum,
            BigDecimal mergeUniqueTransId, String indTrbVrfCd, LocalDateTime wtpyResDueDt, LocalDateTime wtpyResEndDt,
            String typeOfConservatorshipCd, String tribeName, LocalDateTime loadDate) {}

    /// Provisional `@Id` `CASE_NUM`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_PRIMARY_PAYEE")
    public record DDcPrimaryPayee(@Id BigDecimal caseNum, BigDecimal edgNum, BigDecimal historySeq, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, String typeOfAssistanceCd, String issuanceMethodCd,
            String addrDiffFromCaseSw, String addrStNum, String addrStNumFrac, String addrStNm, String addrAptNum,
            String addrLine, String addrCity, String addrZip5, String addrZip4, String addrDwellingTypeCd,
            LocalDateTime payeeBeginDt, LocalDateTime payeeEndDt, LocalDateTime archiveDt, BigDecimal indvId,
            String altPayeeExistsSw, String addrStDirCd, String addrStTypeCd, String addrCountyCd, String addrStateCd,
            String ebtSw, String freezeAddressUpdateSw, String collectPhysicalAddrSw, BigDecimal sequenceNum,
            String addrTypeCd, LocalDateTime loadDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_RELATIONSHIPS")
    public record DDcRelationships(@Id BigDecimal indvId, BigDecimal refIndvId, BigDecimal historySeq,
            String createUserId, String updateUserId, LocalDateTime createDt, LocalDateTime updateDt,
            BigDecimal uniqueTransId, LocalDateTime effBeginDt, LocalDateTime effEndDt, String histNavInd,
            String relationshipTypeCd, String preparesAndPurchasesSw, String fillsParentalRoleSw, String taxDependentSw,
            String relationshipVrfCd, String providesCareForSw, String physAbleToPurchPrepSw, LocalDateTime reportDt,
            LocalDateTime discoveryDt, String timelySw, LocalDateTime archiveDt, String providesSupportForSw,
            LocalDateTime marriageDt, LocalDateTime verfReceivedDt, String isCompleteSw, String livingTogetherSw) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_INDV_ADDR")
    public record DIndvAddr(LocalDateTime updateDt, @Id BigDecimal indvId, String addrStNum, String addrStNumFrac,
            String addrStNm, String addrAptNum, String addrLine, String addrCity, String addrCountyCd,
            String addrStateCd, String addrZip5, String addrZip4, BigDecimal caseNum, String addrDwellingTypeCd,
            String addrStTypeCd, LocalDateTime effBeginDt, LocalDateTime effEndDt, BigDecimal edgNum,
            String etlMappingName, String addrTypeCd, LocalDateTime loadDate, LocalDateTime createDt,
            String addrStDirCd) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_IN_MANAGED_CARE")
    public record DInManagedCare(@Id BigDecimal indvId, String mcProgCode, LocalDateTime beginDt, BigDecimal historySeq,
            String mcEligCode, String mcCandidateFlag, String mcPlan, String mcStatusCd, String mcEventCd,
            LocalDateTime mcEventDt, BigDecimal uniqueTransId, String createUserId, LocalDateTime createDt,
            String providerNum, LocalDateTime endDt, LocalDateTime archiveDt, String mcCountyCd,
            LocalDateTime estimatedEligEndDt, String voluntarySw, String mergeSeparateInd, BigDecimal realIndvId,
            String waiverSw, String mmpCandidateFlag, LocalDateTime loadDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_H_DC_INDV")
    public record HDcIndv(@Id BigDecimal indvId, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, BigDecimal ssn, LocalDateTime dobDt, String lastName, String firstName,
            String sufxName, String prefixName, String midName, String dobVrfCd, String raceCd, String ssaValidationSw,
            String ssnVrfCd, String ethnicityCd, String genderCd, String inactiveInd, BigDecimal empId,
            String fileClearanceSw, BigDecimal chipSeqNum, String mergeSeparateInd, LocalDateTime deathDt,
            String deceasedDtVrfCd, String highneedProfileSw, String highneedCriteriaCd, String mhmrCaseNum,
            LocalDateTime archiveDt, String deleteSw, String fedRcgnzdIndianTribeSw, String splHealthCareEnrolledSw,
            @Column("IN_FC_ON_18TH_BIRTHDAY_SW") String inFcOn18thBirthdaySw,
            @Column("IN_FC_ON_18TH_BRTHDAT_VRF_CD") String inFcOn18thBrthdatVrfCd, String stateCd,
            BigDecimal dfpsPersonId, String maidenName, String mothersMaidenName, String isCompleteSw, String otherRace,
            String inactivateTypeCd, String potentialDuplicateSw, String potentialDuplicateTypeCd,
            LocalDateTime inactivatedDt, String inactivatedByUserId, LocalDateTime potentialDuplicateDt,
            String potentialDuplicateUserId, BigDecimal potentialDupPrimaryId, BigDecimal mergeRequestSeqNum,
            BigDecimal mergeUniqueTransId, String indTrbVrfCd, LocalDateTime wtpyResDueDt, LocalDateTime wtpyResEndDt,
            String typeOfConservatorshipCd, String tribeName, LocalDateTime loadDate) {}
}
