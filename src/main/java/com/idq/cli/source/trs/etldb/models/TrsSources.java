package com.idq.cli.source.trs.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the TRS source tables and views read by
/// `wf_TRS_Stage_Load_1_Ongoing`.
///
/// The mappings read through their `IdqMapInitQuery` records in [TrsQueryRows]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_TRS`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// Tables with the `_D_` (delta detection) infix are named `<Name>Delta` and `_H_` (history) tables `<Name>Hist`:
/// `STG_TRS_DC_CASES` is [DcCases], `STG_TRS_D_DC_CASES` is [DcCasesDelta], `STG_TRS_H_DC_INDV` is [DcIndvHist].
///
/// `STG_TRS_VALID_MEMBERS` and `STG_TRS_D_UNQ_ADDR` are loaded by mappings 001 and 011 before later mappings
/// read them ([ValidMember], [UniqueAddressDelta]). The `C_S_TRS_*` tables the mappings load are in
/// `com.idq.cli.mdmdc.etldb.models.TrsTargets`.
public final class TrsSources {

    private TrsSources() {}

    /// Provisional `@Id` `REF_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_CD_REF")
    public record CdRef(@Id Long refId, String tablename, String code, String description) {

        /// `CdRef.builder().refId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Long refId;
            private String tablename;
            private String code;
            private String description;

            private Builder() {}

            public Builder refId(Long value) { refId = value; return this; }
            public Builder tablename(String value) { tablename = value; return this; }
            public Builder code(String value) { code = value; return this; }
            public Builder description(String value) { description = value; return this; }

            public CdRef build() {
                return new CdRef(refId, tablename, code, description);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_CV_ED_MCI_EDG_INDV")
    public record CvEdMciEdgIndv(@Id BigDecimal indvId, String programCd, BigDecimal edgNum, BigDecimal mciCreateSeq,
            BigDecimal historySeq, BigDecimal caseNum, String partStatusCd, String typeOfAssistanceCd,
            String createUserId, LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt,
            String systemCd, String conversionInd, LocalDateTime eligEffBeginDt, LocalDateTime eligEffEndDt,
            LocalDateTime convertDt, String refugeeInd, String medInd, String saverrMergeId, String processId,
            BigDecimal realIndvId, String processTypeCd, LocalDateTime stgLastUpdateDate) {

        /// `CvEdMciEdgIndv.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private String programCd;
            private BigDecimal edgNum;
            private BigDecimal mciCreateSeq;
            private BigDecimal historySeq;
            private BigDecimal caseNum;
            private String partStatusCd;
            private String typeOfAssistanceCd;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private LocalDateTime archiveDt;
            private String systemCd;
            private String conversionInd;
            private LocalDateTime eligEffBeginDt;
            private LocalDateTime eligEffEndDt;
            private LocalDateTime convertDt;
            private String refugeeInd;
            private String medInd;
            private String saverrMergeId;
            private String processId;
            private BigDecimal realIndvId;
            private String processTypeCd;
            private LocalDateTime stgLastUpdateDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder programCd(String value) { programCd = value; return this; }
            public Builder edgNum(BigDecimal value) { edgNum = value; return this; }
            public Builder mciCreateSeq(BigDecimal value) { mciCreateSeq = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder partStatusCd(String value) { partStatusCd = value; return this; }
            public Builder typeOfAssistanceCd(String value) { typeOfAssistanceCd = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder systemCd(String value) { systemCd = value; return this; }
            public Builder conversionInd(String value) { conversionInd = value; return this; }
            public Builder eligEffBeginDt(LocalDateTime value) { eligEffBeginDt = value; return this; }
            public Builder eligEffEndDt(LocalDateTime value) { eligEffEndDt = value; return this; }
            public Builder convertDt(LocalDateTime value) { convertDt = value; return this; }
            public Builder refugeeInd(String value) { refugeeInd = value; return this; }
            public Builder medInd(String value) { medInd = value; return this; }
            public Builder saverrMergeId(String value) { saverrMergeId = value; return this; }
            public Builder processId(String value) { processId = value; return this; }
            public Builder realIndvId(BigDecimal value) { realIndvId = value; return this; }
            public Builder processTypeCd(String value) { processTypeCd = value; return this; }
            public Builder stgLastUpdateDate(LocalDateTime value) { stgLastUpdateDate = value; return this; }

            public CvEdMciEdgIndv build() {
                return new CvEdMciEdgIndv(indvId, programCd, edgNum, mciCreateSeq, historySeq, caseNum, partStatusCd,
                        typeOfAssistanceCd, createUserId, createDt, uniqueTransId, archiveDt, systemCd, conversionInd,
                        eligEffBeginDt, eligEffEndDt, convertDt, refugeeInd, medInd, saverrMergeId, processId,
                        realIndvId, processTypeCd, stgLastUpdateDate);
            }
        }
    }

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
            LocalDateTime bprComntsRefreshDt, LocalDateTime stgLastUpdateDate) {

        /// `DcCases.builder().caseNum(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal caseNum;
            private BigDecimal historySeq;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private String languageCd;
            private LocalDateTime caseClosedDt;
            private String caseStatusCd;
            private String caseModeCd;
            private String reactivationInd;
            private LocalDateTime reactivationDt;
            private LocalDateTime interviewDt;
            private String authrepFirstName;
            private String authrepLastName;
            private String authrepMidName;
            private String authrepPrefixName;
            private String authrepPhNum;
            private String authrepOrgName;
            private String workPhNum;
            private String otherPhNum;
            private String email;
            private LocalDateTime appRecvdDt;
            private String phNum;
            private BigDecimal officeNum;
            private String authrepIndvIdVrfCd;
            private String authRepSw;
            private LocalDateTime archiveDt;
            private String interviewTypeCd;
            private String dhsEmpCaseSw;
            private String authorizedEmailSw;
            private String authrepSufxName;
            private String unableToLocateSw;
            private BigDecimal workPhNumExt;
            private LocalDateTime actionDt;
            private String authrepWorkNum;
            private String authrepOtherNum;
            private String relationshipIndvCd;
            private String authrepCaregiverSw;
            private String processId;
            private BigDecimal empId;
            private String whpPhNum;
            private String deleteSw;
            private String applicationSignedSw;
            private String mdAllowedSw;
            private String mdExistsSw;
            private String vendorStaffSw;
            private String otherLanguage;
            private BigDecimal disasterSeqNum;
            private String spProgReqTypeCd;
            private String appIntakeInd;
            private String cboSw;
            private String mbccSw;
            private String navigatorSw;
            private String everyoneLiveAtHouseholdSw;
            private String renewalCvgFutureYrsCd;
            private String authRepId;
            private String interpreterLangCd;
            private String sentAuthrepSw;
            private String authrepTypeCd;
            private String authrepVerfCd;
            private LocalDateTime bprComntsRefreshDt;
            private LocalDateTime stgLastUpdateDate;

            private Builder() {}

            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder languageCd(String value) { languageCd = value; return this; }
            public Builder caseClosedDt(LocalDateTime value) { caseClosedDt = value; return this; }
            public Builder caseStatusCd(String value) { caseStatusCd = value; return this; }
            public Builder caseModeCd(String value) { caseModeCd = value; return this; }
            public Builder reactivationInd(String value) { reactivationInd = value; return this; }
            public Builder reactivationDt(LocalDateTime value) { reactivationDt = value; return this; }
            public Builder interviewDt(LocalDateTime value) { interviewDt = value; return this; }
            public Builder authrepFirstName(String value) { authrepFirstName = value; return this; }
            public Builder authrepLastName(String value) { authrepLastName = value; return this; }
            public Builder authrepMidName(String value) { authrepMidName = value; return this; }
            public Builder authrepPrefixName(String value) { authrepPrefixName = value; return this; }
            public Builder authrepPhNum(String value) { authrepPhNum = value; return this; }
            public Builder authrepOrgName(String value) { authrepOrgName = value; return this; }
            public Builder workPhNum(String value) { workPhNum = value; return this; }
            public Builder otherPhNum(String value) { otherPhNum = value; return this; }
            public Builder email(String value) { email = value; return this; }
            public Builder appRecvdDt(LocalDateTime value) { appRecvdDt = value; return this; }
            public Builder phNum(String value) { phNum = value; return this; }
            public Builder officeNum(BigDecimal value) { officeNum = value; return this; }
            public Builder authrepIndvIdVrfCd(String value) { authrepIndvIdVrfCd = value; return this; }
            public Builder authRepSw(String value) { authRepSw = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder interviewTypeCd(String value) { interviewTypeCd = value; return this; }
            public Builder dhsEmpCaseSw(String value) { dhsEmpCaseSw = value; return this; }
            public Builder authorizedEmailSw(String value) { authorizedEmailSw = value; return this; }
            public Builder authrepSufxName(String value) { authrepSufxName = value; return this; }
            public Builder unableToLocateSw(String value) { unableToLocateSw = value; return this; }
            public Builder workPhNumExt(BigDecimal value) { workPhNumExt = value; return this; }
            public Builder actionDt(LocalDateTime value) { actionDt = value; return this; }
            public Builder authrepWorkNum(String value) { authrepWorkNum = value; return this; }
            public Builder authrepOtherNum(String value) { authrepOtherNum = value; return this; }
            public Builder relationshipIndvCd(String value) { relationshipIndvCd = value; return this; }
            public Builder authrepCaregiverSw(String value) { authrepCaregiverSw = value; return this; }
            public Builder processId(String value) { processId = value; return this; }
            public Builder empId(BigDecimal value) { empId = value; return this; }
            public Builder whpPhNum(String value) { whpPhNum = value; return this; }
            public Builder deleteSw(String value) { deleteSw = value; return this; }
            public Builder applicationSignedSw(String value) { applicationSignedSw = value; return this; }
            public Builder mdAllowedSw(String value) { mdAllowedSw = value; return this; }
            public Builder mdExistsSw(String value) { mdExistsSw = value; return this; }
            public Builder vendorStaffSw(String value) { vendorStaffSw = value; return this; }
            public Builder otherLanguage(String value) { otherLanguage = value; return this; }
            public Builder disasterSeqNum(BigDecimal value) { disasterSeqNum = value; return this; }
            public Builder spProgReqTypeCd(String value) { spProgReqTypeCd = value; return this; }
            public Builder appIntakeInd(String value) { appIntakeInd = value; return this; }
            public Builder cboSw(String value) { cboSw = value; return this; }
            public Builder mbccSw(String value) { mbccSw = value; return this; }
            public Builder navigatorSw(String value) { navigatorSw = value; return this; }
            public Builder everyoneLiveAtHouseholdSw(String value) { everyoneLiveAtHouseholdSw = value; return this; }
            public Builder renewalCvgFutureYrsCd(String value) { renewalCvgFutureYrsCd = value; return this; }
            public Builder authRepId(String value) { authRepId = value; return this; }
            public Builder interpreterLangCd(String value) { interpreterLangCd = value; return this; }
            public Builder sentAuthrepSw(String value) { sentAuthrepSw = value; return this; }
            public Builder authrepTypeCd(String value) { authrepTypeCd = value; return this; }
            public Builder authrepVerfCd(String value) { authrepVerfCd = value; return this; }
            public Builder bprComntsRefreshDt(LocalDateTime value) { bprComntsRefreshDt = value; return this; }
            public Builder stgLastUpdateDate(LocalDateTime value) { stgLastUpdateDate = value; return this; }

            public DcCases build() {
                return new DcCases(caseNum, historySeq, createUserId, createDt, uniqueTransId, languageCd, caseClosedDt,
                        caseStatusCd, caseModeCd, reactivationInd, reactivationDt, interviewDt, authrepFirstName,
                        authrepLastName, authrepMidName, authrepPrefixName, authrepPhNum, authrepOrgName, workPhNum,
                        otherPhNum, email, appRecvdDt, phNum, officeNum, authrepIndvIdVrfCd, authRepSw, archiveDt,
                        interviewTypeCd, dhsEmpCaseSw, authorizedEmailSw, authrepSufxName, unableToLocateSw,
                        workPhNumExt, actionDt, authrepWorkNum, authrepOtherNum, relationshipIndvCd, authrepCaregiverSw,
                        processId, empId, whpPhNum, deleteSw, applicationSignedSw, mdAllowedSw, mdExistsSw,
                        vendorStaffSw, otherLanguage, disasterSeqNum, spProgReqTypeCd, appIntakeInd, cboSw, mbccSw,
                        navigatorSw, everyoneLiveAtHouseholdSw, renewalCvgFutureYrsCd, authRepId, interpreterLangCd,
                        sentAuthrepSw, authrepTypeCd, authrepVerfCd, bprComntsRefreshDt, stgLastUpdateDate);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_DC_CASE_INDV")
    public record DcCaseIndv(@Id BigDecimal indvId, BigDecimal caseNum, BigDecimal historySeq, String activeInCaseSw,
            String createUserId, String updateUserId, LocalDateTime createDt, LocalDateTime updateDt,
            BigDecimal uniqueTransId, LocalDateTime effBeginDt, LocalDateTime effEndDt, String histNavInd,
            String headOfHouseholdSw, String employeeSw, LocalDateTime archiveDt, String inactiveReasonCds,
            String reactiveDeceasedMaReqSw, String isPermissionReqdSw, String eldsPermissionProvSw,
            LocalDateTime stgLastUpdateDate) {

        /// `DcCaseIndv.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal caseNum;
            private BigDecimal historySeq;
            private String activeInCaseSw;
            private String createUserId;
            private String updateUserId;
            private LocalDateTime createDt;
            private LocalDateTime updateDt;
            private BigDecimal uniqueTransId;
            private LocalDateTime effBeginDt;
            private LocalDateTime effEndDt;
            private String histNavInd;
            private String headOfHouseholdSw;
            private String employeeSw;
            private LocalDateTime archiveDt;
            private String inactiveReasonCds;
            private String reactiveDeceasedMaReqSw;
            private String isPermissionReqdSw;
            private String eldsPermissionProvSw;
            private LocalDateTime stgLastUpdateDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder activeInCaseSw(String value) { activeInCaseSw = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder updateUserId(String value) { updateUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder updateDt(LocalDateTime value) { updateDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder effBeginDt(LocalDateTime value) { effBeginDt = value; return this; }
            public Builder effEndDt(LocalDateTime value) { effEndDt = value; return this; }
            public Builder histNavInd(String value) { histNavInd = value; return this; }
            public Builder headOfHouseholdSw(String value) { headOfHouseholdSw = value; return this; }
            public Builder employeeSw(String value) { employeeSw = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder inactiveReasonCds(String value) { inactiveReasonCds = value; return this; }
            public Builder reactiveDeceasedMaReqSw(String value) { reactiveDeceasedMaReqSw = value; return this; }
            public Builder isPermissionReqdSw(String value) { isPermissionReqdSw = value; return this; }
            public Builder eldsPermissionProvSw(String value) { eldsPermissionProvSw = value; return this; }
            public Builder stgLastUpdateDate(LocalDateTime value) { stgLastUpdateDate = value; return this; }

            public DcCaseIndv build() {
                return new DcCaseIndv(indvId, caseNum, historySeq, activeInCaseSw, createUserId, updateUserId, createDt,
                        updateDt, uniqueTransId, effBeginDt, effEndDt, histNavInd, headOfHouseholdSw, employeeSw,
                        archiveDt, inactiveReasonCds, reactiveDeceasedMaReqSw, isPermissionReqdSw, eldsPermissionProvSw,
                        stgLastUpdateDate);
            }
        }
    }

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
    public record CvDcMciAliasDelta(@Id BigDecimal indvId, BigDecimal sequenceNum, BigDecimal historySeq, String firstName,
            String midName, String lastName, String sufxName, String prefixName, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt, String saverrMessageId) {

        /// `CvDcMciAliasDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal sequenceNum;
            private BigDecimal historySeq;
            private String firstName;
            private String midName;
            private String lastName;
            private String sufxName;
            private String prefixName;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private LocalDateTime archiveDt;
            private String saverrMessageId;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder sequenceNum(BigDecimal value) { sequenceNum = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder midName(String value) { midName = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder sufxName(String value) { sufxName = value; return this; }
            public Builder prefixName(String value) { prefixName = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder saverrMessageId(String value) { saverrMessageId = value; return this; }

            public CvDcMciAliasDelta build() {
                return new CvDcMciAliasDelta(indvId, sequenceNum, historySeq, firstName, midName, lastName, sufxName,
                        prefixName, createUserId, createDt, uniqueTransId, archiveDt, saverrMessageId);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_DC_MCI_INDV")
    public record CvDcMciIndvDelta(@Id BigDecimal indvId, BigDecimal historySeq, String firstName, String midName,
            String lastName, String sufxName, String prefixName, BigDecimal ssn, String genderCd, LocalDateTime dobDt,
            String raceCd, String ethnicityCd, LocalDateTime otTanfDt, BigDecimal fipsCntyCd, LocalDateTime twConvertDt,
            LocalDateTime ltcConvertDt, String createSystemCd, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, String twConvertInd, LocalDateTime archiveDt, String ltcConvertInd,
            String inactiveInd, String saverrMessageId, LocalDateTime fsConvertDt, LocalDateTime maConvertDt,
            LocalDateTime meConvertDt, LocalDateTime ccConvertDt, LocalDateTime mcConvertDt, LocalDateTime tfConvertDt,
            String inactivateTypeCd, String potentialDuplicateSw, String potentialDuplicateTypeCd,
            LocalDateTime inactivatedDt, String inactivatedByUserId, LocalDateTime potentialDuplicateDt,
            String potentialDuplicateUserId, BigDecimal potentialDupPrimaryId, LocalDateTime chConvertDt) {

        /// `CvDcMciIndvDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal historySeq;
            private String firstName;
            private String midName;
            private String lastName;
            private String sufxName;
            private String prefixName;
            private BigDecimal ssn;
            private String genderCd;
            private LocalDateTime dobDt;
            private String raceCd;
            private String ethnicityCd;
            private LocalDateTime otTanfDt;
            private BigDecimal fipsCntyCd;
            private LocalDateTime twConvertDt;
            private LocalDateTime ltcConvertDt;
            private String createSystemCd;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private String twConvertInd;
            private LocalDateTime archiveDt;
            private String ltcConvertInd;
            private String inactiveInd;
            private String saverrMessageId;
            private LocalDateTime fsConvertDt;
            private LocalDateTime maConvertDt;
            private LocalDateTime meConvertDt;
            private LocalDateTime ccConvertDt;
            private LocalDateTime mcConvertDt;
            private LocalDateTime tfConvertDt;
            private String inactivateTypeCd;
            private String potentialDuplicateSw;
            private String potentialDuplicateTypeCd;
            private LocalDateTime inactivatedDt;
            private String inactivatedByUserId;
            private LocalDateTime potentialDuplicateDt;
            private String potentialDuplicateUserId;
            private BigDecimal potentialDupPrimaryId;
            private LocalDateTime chConvertDt;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder midName(String value) { midName = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder sufxName(String value) { sufxName = value; return this; }
            public Builder prefixName(String value) { prefixName = value; return this; }
            public Builder ssn(BigDecimal value) { ssn = value; return this; }
            public Builder genderCd(String value) { genderCd = value; return this; }
            public Builder dobDt(LocalDateTime value) { dobDt = value; return this; }
            public Builder raceCd(String value) { raceCd = value; return this; }
            public Builder ethnicityCd(String value) { ethnicityCd = value; return this; }
            public Builder otTanfDt(LocalDateTime value) { otTanfDt = value; return this; }
            public Builder fipsCntyCd(BigDecimal value) { fipsCntyCd = value; return this; }
            public Builder twConvertDt(LocalDateTime value) { twConvertDt = value; return this; }
            public Builder ltcConvertDt(LocalDateTime value) { ltcConvertDt = value; return this; }
            public Builder createSystemCd(String value) { createSystemCd = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder twConvertInd(String value) { twConvertInd = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder ltcConvertInd(String value) { ltcConvertInd = value; return this; }
            public Builder inactiveInd(String value) { inactiveInd = value; return this; }
            public Builder saverrMessageId(String value) { saverrMessageId = value; return this; }
            public Builder fsConvertDt(LocalDateTime value) { fsConvertDt = value; return this; }
            public Builder maConvertDt(LocalDateTime value) { maConvertDt = value; return this; }
            public Builder meConvertDt(LocalDateTime value) { meConvertDt = value; return this; }
            public Builder ccConvertDt(LocalDateTime value) { ccConvertDt = value; return this; }
            public Builder mcConvertDt(LocalDateTime value) { mcConvertDt = value; return this; }
            public Builder tfConvertDt(LocalDateTime value) { tfConvertDt = value; return this; }
            public Builder inactivateTypeCd(String value) { inactivateTypeCd = value; return this; }
            public Builder potentialDuplicateSw(String value) { potentialDuplicateSw = value; return this; }
            public Builder potentialDuplicateTypeCd(String value) { potentialDuplicateTypeCd = value; return this; }
            public Builder inactivatedDt(LocalDateTime value) { inactivatedDt = value; return this; }
            public Builder inactivatedByUserId(String value) { inactivatedByUserId = value; return this; }
            public Builder potentialDuplicateDt(LocalDateTime value) { potentialDuplicateDt = value; return this; }
            public Builder potentialDuplicateUserId(String value) { potentialDuplicateUserId = value; return this; }
            public Builder potentialDupPrimaryId(BigDecimal value) { potentialDupPrimaryId = value; return this; }
            public Builder chConvertDt(LocalDateTime value) { chConvertDt = value; return this; }

            public CvDcMciIndvDelta build() {
                return new CvDcMciIndvDelta(indvId, historySeq, firstName, midName, lastName, sufxName, prefixName, ssn,
                        genderCd, dobDt, raceCd, ethnicityCd, otTanfDt, fipsCntyCd, twConvertDt, ltcConvertDt,
                        createSystemCd, createUserId, createDt, uniqueTransId, twConvertInd, archiveDt, ltcConvertInd,
                        inactiveInd, saverrMessageId, fsConvertDt, maConvertDt, meConvertDt, ccConvertDt, mcConvertDt,
                        tfConvertDt, inactivateTypeCd, potentialDuplicateSw, potentialDuplicateTypeCd, inactivatedDt,
                        inactivatedByUserId, potentialDuplicateDt, potentialDuplicateUserId, potentialDupPrimaryId,
                        chConvertDt);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_DC_MRG_SPRT_INDV")
    public record CvDcMrgSprtIndvDelta(@Id BigDecimal indvId, BigDecimal oldIndvId, BigDecimal sequenceNum, String typeCd,
            BigDecimal historySeq, LocalDateTime mergeSeparateDt, String createUserId, LocalDateTime createDt,
            BigDecimal uniqueTransId, String saverrMessageId, String primaryIndvSw, LocalDateTime archiveDt) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_ED_MCI_EDG_INDV")
    public record CvEdMciEdgIndvDelta(@Id BigDecimal indvId, String programCd, BigDecimal edgNum, BigDecimal mciCreateSeq,
            BigDecimal historySeq, BigDecimal caseNum, String partStatusCd, String typeOfAssistanceCd,
            String createUserId, LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt,
            String systemCd, String conversionInd, LocalDateTime eligEffBeginDt, LocalDateTime eligEffEndDt,
            LocalDateTime convertDt, String refugeeInd, String medInd, String saverrMergeId, String processId,
            BigDecimal realIndvId, String processTypeCd, LocalDateTime loadDate) {}

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_CV_MCI_EDG_INDV_TOA")
    public record CvMciEdgIndvToaDelta(@Id BigDecimal indvId, String programCd, BigDecimal edgNum, BigDecimal mciCreateSeq,
            BigDecimal historySeq, BigDecimal caseNum, String partStatusCd, String typeOfAssistanceCd,
            String createUserId, LocalDateTime createDt, BigDecimal uniqueTransId, LocalDateTime archiveDt,
            String systemCd, String conversionInd, LocalDateTime eligEffBeginDt, LocalDateTime eligEffEndDt,
            LocalDateTime convertDt, String refugeeInd, String medInd, String saverrMergeId, String processId,
            BigDecimal realIndvId, String processTypeCd, LocalDateTime loadDate) {

        /// `CvMciEdgIndvToaDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private String programCd;
            private BigDecimal edgNum;
            private BigDecimal mciCreateSeq;
            private BigDecimal historySeq;
            private BigDecimal caseNum;
            private String partStatusCd;
            private String typeOfAssistanceCd;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private LocalDateTime archiveDt;
            private String systemCd;
            private String conversionInd;
            private LocalDateTime eligEffBeginDt;
            private LocalDateTime eligEffEndDt;
            private LocalDateTime convertDt;
            private String refugeeInd;
            private String medInd;
            private String saverrMergeId;
            private String processId;
            private BigDecimal realIndvId;
            private String processTypeCd;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder programCd(String value) { programCd = value; return this; }
            public Builder edgNum(BigDecimal value) { edgNum = value; return this; }
            public Builder mciCreateSeq(BigDecimal value) { mciCreateSeq = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder partStatusCd(String value) { partStatusCd = value; return this; }
            public Builder typeOfAssistanceCd(String value) { typeOfAssistanceCd = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder systemCd(String value) { systemCd = value; return this; }
            public Builder conversionInd(String value) { conversionInd = value; return this; }
            public Builder eligEffBeginDt(LocalDateTime value) { eligEffBeginDt = value; return this; }
            public Builder eligEffEndDt(LocalDateTime value) { eligEffEndDt = value; return this; }
            public Builder convertDt(LocalDateTime value) { convertDt = value; return this; }
            public Builder refugeeInd(String value) { refugeeInd = value; return this; }
            public Builder medInd(String value) { medInd = value; return this; }
            public Builder saverrMergeId(String value) { saverrMergeId = value; return this; }
            public Builder processId(String value) { processId = value; return this; }
            public Builder realIndvId(BigDecimal value) { realIndvId = value; return this; }
            public Builder processTypeCd(String value) { processTypeCd = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public CvMciEdgIndvToaDelta build() {
                return new CvMciEdgIndvToaDelta(indvId, programCd, edgNum, mciCreateSeq, historySeq, caseNum,
                        partStatusCd, typeOfAssistanceCd, createUserId, createDt, uniqueTransId, archiveDt, systemCd,
                        conversionInd, eligEffBeginDt, eligEffEndDt, convertDt, refugeeInd, medInd, saverrMergeId,
                        processId, realIndvId, processTypeCd, loadDate);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_ALIAS")
    public record DcAliasDelta(@Id BigDecimal indvId, BigDecimal seqNum, BigDecimal historySeq, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, String lastName, String firstName, String sufxName,
            String prefixName, String midName, BigDecimal aliasIndvId, LocalDateTime archiveDt, String isCompleteSw,
            LocalDateTime loadDate) {

        /// `DcAliasDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal seqNum;
            private BigDecimal historySeq;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private String lastName;
            private String firstName;
            private String sufxName;
            private String prefixName;
            private String midName;
            private BigDecimal aliasIndvId;
            private LocalDateTime archiveDt;
            private String isCompleteSw;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder seqNum(BigDecimal value) { seqNum = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder sufxName(String value) { sufxName = value; return this; }
            public Builder prefixName(String value) { prefixName = value; return this; }
            public Builder midName(String value) { midName = value; return this; }
            public Builder aliasIndvId(BigDecimal value) { aliasIndvId = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder isCompleteSw(String value) { isCompleteSw = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public DcAliasDelta build() {
                return new DcAliasDelta(indvId, seqNum, historySeq, createUserId, createDt, uniqueTransId, lastName,
                        firstName, sufxName, prefixName, midName, aliasIndvId, archiveDt, isCompleteSw, loadDate);
            }
        }
    }

    /// Provisional `@Id` `CASE_NUM`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_CASES")
    public record DcCasesDelta(@Id BigDecimal caseNum, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
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
            LocalDateTime bprComntsRefreshDt, LocalDateTime loadDate) {

        /// `DcCasesDelta.builder().caseNum(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal caseNum;
            private BigDecimal historySeq;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private String languageCd;
            private LocalDateTime caseClosedDt;
            private String caseStatusCd;
            private String caseModeCd;
            private String reactivationInd;
            private LocalDateTime reactivationDt;
            private LocalDateTime interviewDt;
            private String authrepFirstName;
            private String authrepLastName;
            private String authrepMidName;
            private String authrepPrefixName;
            private String authrepPhNum;
            private String authrepOrgName;
            private String workPhNum;
            private String otherPhNum;
            private String email;
            private LocalDateTime appRecvdDt;
            private String phNum;
            private BigDecimal officeNum;
            private String authrepIndvIdVrfCd;
            private String authRepSw;
            private LocalDateTime archiveDt;
            private String interviewTypeCd;
            private String dhsEmpCaseSw;
            private String authorizedEmailSw;
            private String authrepSufxName;
            private String unableToLocateSw;
            private BigDecimal workPhNumExt;
            private LocalDateTime actionDt;
            private String authrepWorkNum;
            private String authrepOtherNum;
            private String relationshipIndvCd;
            private String authrepCaregiverSw;
            private String processId;
            private BigDecimal empId;
            private String whpPhNum;
            private String deleteSw;
            private String applicationSignedSw;
            private String mdAllowedSw;
            private String mdExistsSw;
            private String vendorStaffSw;
            private String otherLanguage;
            private BigDecimal disasterSeqNum;
            private String spProgReqTypeCd;
            private String appIntakeInd;
            private String cboSw;
            private String mbccSw;
            private String navigatorSw;
            private String everyoneLiveAtHouseholdSw;
            private String renewalCvgFutureYrsCd;
            private String authRepId;
            private String interpreterLangCd;
            private String sentAuthrepSw;
            private String authrepTypeCd;
            private String authrepVerfCd;
            private LocalDateTime bprComntsRefreshDt;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder languageCd(String value) { languageCd = value; return this; }
            public Builder caseClosedDt(LocalDateTime value) { caseClosedDt = value; return this; }
            public Builder caseStatusCd(String value) { caseStatusCd = value; return this; }
            public Builder caseModeCd(String value) { caseModeCd = value; return this; }
            public Builder reactivationInd(String value) { reactivationInd = value; return this; }
            public Builder reactivationDt(LocalDateTime value) { reactivationDt = value; return this; }
            public Builder interviewDt(LocalDateTime value) { interviewDt = value; return this; }
            public Builder authrepFirstName(String value) { authrepFirstName = value; return this; }
            public Builder authrepLastName(String value) { authrepLastName = value; return this; }
            public Builder authrepMidName(String value) { authrepMidName = value; return this; }
            public Builder authrepPrefixName(String value) { authrepPrefixName = value; return this; }
            public Builder authrepPhNum(String value) { authrepPhNum = value; return this; }
            public Builder authrepOrgName(String value) { authrepOrgName = value; return this; }
            public Builder workPhNum(String value) { workPhNum = value; return this; }
            public Builder otherPhNum(String value) { otherPhNum = value; return this; }
            public Builder email(String value) { email = value; return this; }
            public Builder appRecvdDt(LocalDateTime value) { appRecvdDt = value; return this; }
            public Builder phNum(String value) { phNum = value; return this; }
            public Builder officeNum(BigDecimal value) { officeNum = value; return this; }
            public Builder authrepIndvIdVrfCd(String value) { authrepIndvIdVrfCd = value; return this; }
            public Builder authRepSw(String value) { authRepSw = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder interviewTypeCd(String value) { interviewTypeCd = value; return this; }
            public Builder dhsEmpCaseSw(String value) { dhsEmpCaseSw = value; return this; }
            public Builder authorizedEmailSw(String value) { authorizedEmailSw = value; return this; }
            public Builder authrepSufxName(String value) { authrepSufxName = value; return this; }
            public Builder unableToLocateSw(String value) { unableToLocateSw = value; return this; }
            public Builder workPhNumExt(BigDecimal value) { workPhNumExt = value; return this; }
            public Builder actionDt(LocalDateTime value) { actionDt = value; return this; }
            public Builder authrepWorkNum(String value) { authrepWorkNum = value; return this; }
            public Builder authrepOtherNum(String value) { authrepOtherNum = value; return this; }
            public Builder relationshipIndvCd(String value) { relationshipIndvCd = value; return this; }
            public Builder authrepCaregiverSw(String value) { authrepCaregiverSw = value; return this; }
            public Builder processId(String value) { processId = value; return this; }
            public Builder empId(BigDecimal value) { empId = value; return this; }
            public Builder whpPhNum(String value) { whpPhNum = value; return this; }
            public Builder deleteSw(String value) { deleteSw = value; return this; }
            public Builder applicationSignedSw(String value) { applicationSignedSw = value; return this; }
            public Builder mdAllowedSw(String value) { mdAllowedSw = value; return this; }
            public Builder mdExistsSw(String value) { mdExistsSw = value; return this; }
            public Builder vendorStaffSw(String value) { vendorStaffSw = value; return this; }
            public Builder otherLanguage(String value) { otherLanguage = value; return this; }
            public Builder disasterSeqNum(BigDecimal value) { disasterSeqNum = value; return this; }
            public Builder spProgReqTypeCd(String value) { spProgReqTypeCd = value; return this; }
            public Builder appIntakeInd(String value) { appIntakeInd = value; return this; }
            public Builder cboSw(String value) { cboSw = value; return this; }
            public Builder mbccSw(String value) { mbccSw = value; return this; }
            public Builder navigatorSw(String value) { navigatorSw = value; return this; }
            public Builder everyoneLiveAtHouseholdSw(String value) { everyoneLiveAtHouseholdSw = value; return this; }
            public Builder renewalCvgFutureYrsCd(String value) { renewalCvgFutureYrsCd = value; return this; }
            public Builder authRepId(String value) { authRepId = value; return this; }
            public Builder interpreterLangCd(String value) { interpreterLangCd = value; return this; }
            public Builder sentAuthrepSw(String value) { sentAuthrepSw = value; return this; }
            public Builder authrepTypeCd(String value) { authrepTypeCd = value; return this; }
            public Builder authrepVerfCd(String value) { authrepVerfCd = value; return this; }
            public Builder bprComntsRefreshDt(LocalDateTime value) { bprComntsRefreshDt = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public DcCasesDelta build() {
                return new DcCasesDelta(caseNum, historySeq, createUserId, createDt, uniqueTransId, languageCd,
                        caseClosedDt, caseStatusCd, caseModeCd, reactivationInd, reactivationDt, interviewDt,
                        authrepFirstName, authrepLastName, authrepMidName, authrepPrefixName, authrepPhNum,
                        authrepOrgName, workPhNum, otherPhNum, email, appRecvdDt, phNum, officeNum, authrepIndvIdVrfCd,
                        authRepSw, archiveDt, interviewTypeCd, dhsEmpCaseSw, authorizedEmailSw, authrepSufxName,
                        unableToLocateSw, workPhNumExt, actionDt, authrepWorkNum, authrepOtherNum, relationshipIndvCd,
                        authrepCaregiverSw, processId, empId, whpPhNum, deleteSw, applicationSignedSw, mdAllowedSw,
                        mdExistsSw, vendorStaffSw, otherLanguage, disasterSeqNum, spProgReqTypeCd, appIntakeInd, cboSw,
                        mbccSw, navigatorSw, everyoneLiveAtHouseholdSw, renewalCvgFutureYrsCd, authRepId,
                        interpreterLangCd, sentAuthrepSw, authrepTypeCd, authrepVerfCd, bprComntsRefreshDt, loadDate);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_INDV")
    public record DcIndvDelta(@Id BigDecimal indvId, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
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
            String typeOfConservatorshipCd, String tribeName, LocalDateTime loadDate) {

        /// `DcIndvDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal historySeq;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private BigDecimal ssn;
            private LocalDateTime dobDt;
            private String lastName;
            private String firstName;
            private String sufxName;
            private String prefixName;
            private String midName;
            private String dobVrfCd;
            private String raceCd;
            private String ssaValidationSw;
            private String ssnVrfCd;
            private String ethnicityCd;
            private String genderCd;
            private String inactiveInd;
            private BigDecimal empId;
            private String fileClearanceSw;
            private BigDecimal chipSeqNum;
            private String mergeSeparateInd;
            private LocalDateTime deathDt;
            private String deceasedDtVrfCd;
            private String highneedProfileSw;
            private String highneedCriteriaCd;
            private String mhmrCaseNum;
            private LocalDateTime archiveDt;
            private String deleteSw;
            private String fedRcgnzdIndianTribeSw;
            private String splHealthCareEnrolledSw;
            private String inFcOn18thBirthdaySw;
            private String inFcOn18thBrthdatVrfCd;
            private String stateCd;
            private BigDecimal dfpsPersonId;
            private String maidenName;
            private String mothersMaidenName;
            private String isCompleteSw;
            private String otherRace;
            private String inactivateTypeCd;
            private String potentialDuplicateSw;
            private String potentialDuplicateTypeCd;
            private LocalDateTime inactivatedDt;
            private String inactivatedByUserId;
            private LocalDateTime potentialDuplicateDt;
            private String potentialDuplicateUserId;
            private BigDecimal potentialDupPrimaryId;
            private BigDecimal mergeRequestSeqNum;
            private BigDecimal mergeUniqueTransId;
            private String indTrbVrfCd;
            private LocalDateTime wtpyResDueDt;
            private LocalDateTime wtpyResEndDt;
            private String typeOfConservatorshipCd;
            private String tribeName;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder ssn(BigDecimal value) { ssn = value; return this; }
            public Builder dobDt(LocalDateTime value) { dobDt = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder sufxName(String value) { sufxName = value; return this; }
            public Builder prefixName(String value) { prefixName = value; return this; }
            public Builder midName(String value) { midName = value; return this; }
            public Builder dobVrfCd(String value) { dobVrfCd = value; return this; }
            public Builder raceCd(String value) { raceCd = value; return this; }
            public Builder ssaValidationSw(String value) { ssaValidationSw = value; return this; }
            public Builder ssnVrfCd(String value) { ssnVrfCd = value; return this; }
            public Builder ethnicityCd(String value) { ethnicityCd = value; return this; }
            public Builder genderCd(String value) { genderCd = value; return this; }
            public Builder inactiveInd(String value) { inactiveInd = value; return this; }
            public Builder empId(BigDecimal value) { empId = value; return this; }
            public Builder fileClearanceSw(String value) { fileClearanceSw = value; return this; }
            public Builder chipSeqNum(BigDecimal value) { chipSeqNum = value; return this; }
            public Builder mergeSeparateInd(String value) { mergeSeparateInd = value; return this; }
            public Builder deathDt(LocalDateTime value) { deathDt = value; return this; }
            public Builder deceasedDtVrfCd(String value) { deceasedDtVrfCd = value; return this; }
            public Builder highneedProfileSw(String value) { highneedProfileSw = value; return this; }
            public Builder highneedCriteriaCd(String value) { highneedCriteriaCd = value; return this; }
            public Builder mhmrCaseNum(String value) { mhmrCaseNum = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder deleteSw(String value) { deleteSw = value; return this; }
            public Builder fedRcgnzdIndianTribeSw(String value) { fedRcgnzdIndianTribeSw = value; return this; }
            public Builder splHealthCareEnrolledSw(String value) { splHealthCareEnrolledSw = value; return this; }
            public Builder inFcOn18thBirthdaySw(String value) { inFcOn18thBirthdaySw = value; return this; }
            public Builder inFcOn18thBrthdatVrfCd(String value) { inFcOn18thBrthdatVrfCd = value; return this; }
            public Builder stateCd(String value) { stateCd = value; return this; }
            public Builder dfpsPersonId(BigDecimal value) { dfpsPersonId = value; return this; }
            public Builder maidenName(String value) { maidenName = value; return this; }
            public Builder mothersMaidenName(String value) { mothersMaidenName = value; return this; }
            public Builder isCompleteSw(String value) { isCompleteSw = value; return this; }
            public Builder otherRace(String value) { otherRace = value; return this; }
            public Builder inactivateTypeCd(String value) { inactivateTypeCd = value; return this; }
            public Builder potentialDuplicateSw(String value) { potentialDuplicateSw = value; return this; }
            public Builder potentialDuplicateTypeCd(String value) { potentialDuplicateTypeCd = value; return this; }
            public Builder inactivatedDt(LocalDateTime value) { inactivatedDt = value; return this; }
            public Builder inactivatedByUserId(String value) { inactivatedByUserId = value; return this; }
            public Builder potentialDuplicateDt(LocalDateTime value) { potentialDuplicateDt = value; return this; }
            public Builder potentialDuplicateUserId(String value) { potentialDuplicateUserId = value; return this; }
            public Builder potentialDupPrimaryId(BigDecimal value) { potentialDupPrimaryId = value; return this; }
            public Builder mergeRequestSeqNum(BigDecimal value) { mergeRequestSeqNum = value; return this; }
            public Builder mergeUniqueTransId(BigDecimal value) { mergeUniqueTransId = value; return this; }
            public Builder indTrbVrfCd(String value) { indTrbVrfCd = value; return this; }
            public Builder wtpyResDueDt(LocalDateTime value) { wtpyResDueDt = value; return this; }
            public Builder wtpyResEndDt(LocalDateTime value) { wtpyResEndDt = value; return this; }
            public Builder typeOfConservatorshipCd(String value) { typeOfConservatorshipCd = value; return this; }
            public Builder tribeName(String value) { tribeName = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public DcIndvDelta build() {
                return new DcIndvDelta(indvId, historySeq, createUserId, createDt, uniqueTransId, ssn, dobDt, lastName,
                        firstName, sufxName, prefixName, midName, dobVrfCd, raceCd, ssaValidationSw, ssnVrfCd,
                        ethnicityCd, genderCd, inactiveInd, empId, fileClearanceSw, chipSeqNum, mergeSeparateInd,
                        deathDt, deceasedDtVrfCd, highneedProfileSw, highneedCriteriaCd, mhmrCaseNum, archiveDt,
                        deleteSw, fedRcgnzdIndianTribeSw, splHealthCareEnrolledSw, inFcOn18thBirthdaySw,
                        inFcOn18thBrthdatVrfCd, stateCd, dfpsPersonId, maidenName, mothersMaidenName, isCompleteSw,
                        otherRace, inactivateTypeCd, potentialDuplicateSw, potentialDuplicateTypeCd, inactivatedDt,
                        inactivatedByUserId, potentialDuplicateDt, potentialDuplicateUserId, potentialDupPrimaryId,
                        mergeRequestSeqNum, mergeUniqueTransId, indTrbVrfCd, wtpyResDueDt, wtpyResEndDt,
                        typeOfConservatorshipCd, tribeName, loadDate);
            }
        }
    }

    /// Provisional `@Id` `CASE_NUM`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_PRIMARY_PAYEE")
    public record DcPrimaryPayeeDelta(@Id BigDecimal caseNum, BigDecimal edgNum, BigDecimal historySeq, String createUserId,
            LocalDateTime createDt, BigDecimal uniqueTransId, String typeOfAssistanceCd, String issuanceMethodCd,
            String addrDiffFromCaseSw, String addrStNum, String addrStNumFrac, String addrStNm, String addrAptNum,
            String addrLine, String addrCity, String addrZip5, String addrZip4, String addrDwellingTypeCd,
            LocalDateTime payeeBeginDt, LocalDateTime payeeEndDt, LocalDateTime archiveDt, BigDecimal indvId,
            String altPayeeExistsSw, String addrStDirCd, String addrStTypeCd, String addrCountyCd, String addrStateCd,
            String ebtSw, String freezeAddressUpdateSw, String collectPhysicalAddrSw, BigDecimal sequenceNum,
            String addrTypeCd, LocalDateTime loadDate) {

        /// `DcPrimaryPayeeDelta.builder().caseNum(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal caseNum;
            private BigDecimal edgNum;
            private BigDecimal historySeq;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private String typeOfAssistanceCd;
            private String issuanceMethodCd;
            private String addrDiffFromCaseSw;
            private String addrStNum;
            private String addrStNumFrac;
            private String addrStNm;
            private String addrAptNum;
            private String addrLine;
            private String addrCity;
            private String addrZip5;
            private String addrZip4;
            private String addrDwellingTypeCd;
            private LocalDateTime payeeBeginDt;
            private LocalDateTime payeeEndDt;
            private LocalDateTime archiveDt;
            private BigDecimal indvId;
            private String altPayeeExistsSw;
            private String addrStDirCd;
            private String addrStTypeCd;
            private String addrCountyCd;
            private String addrStateCd;
            private String ebtSw;
            private String freezeAddressUpdateSw;
            private String collectPhysicalAddrSw;
            private BigDecimal sequenceNum;
            private String addrTypeCd;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder edgNum(BigDecimal value) { edgNum = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder typeOfAssistanceCd(String value) { typeOfAssistanceCd = value; return this; }
            public Builder issuanceMethodCd(String value) { issuanceMethodCd = value; return this; }
            public Builder addrDiffFromCaseSw(String value) { addrDiffFromCaseSw = value; return this; }
            public Builder addrStNum(String value) { addrStNum = value; return this; }
            public Builder addrStNumFrac(String value) { addrStNumFrac = value; return this; }
            public Builder addrStNm(String value) { addrStNm = value; return this; }
            public Builder addrAptNum(String value) { addrAptNum = value; return this; }
            public Builder addrLine(String value) { addrLine = value; return this; }
            public Builder addrCity(String value) { addrCity = value; return this; }
            public Builder addrZip5(String value) { addrZip5 = value; return this; }
            public Builder addrZip4(String value) { addrZip4 = value; return this; }
            public Builder addrDwellingTypeCd(String value) { addrDwellingTypeCd = value; return this; }
            public Builder payeeBeginDt(LocalDateTime value) { payeeBeginDt = value; return this; }
            public Builder payeeEndDt(LocalDateTime value) { payeeEndDt = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder altPayeeExistsSw(String value) { altPayeeExistsSw = value; return this; }
            public Builder addrStDirCd(String value) { addrStDirCd = value; return this; }
            public Builder addrStTypeCd(String value) { addrStTypeCd = value; return this; }
            public Builder addrCountyCd(String value) { addrCountyCd = value; return this; }
            public Builder addrStateCd(String value) { addrStateCd = value; return this; }
            public Builder ebtSw(String value) { ebtSw = value; return this; }
            public Builder freezeAddressUpdateSw(String value) { freezeAddressUpdateSw = value; return this; }
            public Builder collectPhysicalAddrSw(String value) { collectPhysicalAddrSw = value; return this; }
            public Builder sequenceNum(BigDecimal value) { sequenceNum = value; return this; }
            public Builder addrTypeCd(String value) { addrTypeCd = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public DcPrimaryPayeeDelta build() {
                return new DcPrimaryPayeeDelta(caseNum, edgNum, historySeq, createUserId, createDt, uniqueTransId,
                        typeOfAssistanceCd, issuanceMethodCd, addrDiffFromCaseSw, addrStNum, addrStNumFrac, addrStNm,
                        addrAptNum, addrLine, addrCity, addrZip5, addrZip4, addrDwellingTypeCd, payeeBeginDt,
                        payeeEndDt, archiveDt, indvId, altPayeeExistsSw, addrStDirCd, addrStTypeCd, addrCountyCd,
                        addrStateCd, ebtSw, freezeAddressUpdateSw, collectPhysicalAddrSw, sequenceNum, addrTypeCd,
                        loadDate);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_DC_RELATIONSHIPS")
    public record DcRelationshipsDelta(@Id BigDecimal indvId, BigDecimal refIndvId, BigDecimal historySeq,
            String createUserId, String updateUserId, LocalDateTime createDt, LocalDateTime updateDt,
            BigDecimal uniqueTransId, LocalDateTime effBeginDt, LocalDateTime effEndDt, String histNavInd,
            String relationshipTypeCd, String preparesAndPurchasesSw, String fillsParentalRoleSw, String taxDependentSw,
            String relationshipVrfCd, String providesCareForSw, String physAbleToPurchPrepSw, LocalDateTime reportDt,
            LocalDateTime discoveryDt, String timelySw, LocalDateTime archiveDt, String providesSupportForSw,
            LocalDateTime marriageDt, LocalDateTime verfReceivedDt, String isCompleteSw, String livingTogetherSw) {

        /// `DcRelationshipsDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal refIndvId;
            private BigDecimal historySeq;
            private String createUserId;
            private String updateUserId;
            private LocalDateTime createDt;
            private LocalDateTime updateDt;
            private BigDecimal uniqueTransId;
            private LocalDateTime effBeginDt;
            private LocalDateTime effEndDt;
            private String histNavInd;
            private String relationshipTypeCd;
            private String preparesAndPurchasesSw;
            private String fillsParentalRoleSw;
            private String taxDependentSw;
            private String relationshipVrfCd;
            private String providesCareForSw;
            private String physAbleToPurchPrepSw;
            private LocalDateTime reportDt;
            private LocalDateTime discoveryDt;
            private String timelySw;
            private LocalDateTime archiveDt;
            private String providesSupportForSw;
            private LocalDateTime marriageDt;
            private LocalDateTime verfReceivedDt;
            private String isCompleteSw;
            private String livingTogetherSw;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder refIndvId(BigDecimal value) { refIndvId = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder updateUserId(String value) { updateUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder updateDt(LocalDateTime value) { updateDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder effBeginDt(LocalDateTime value) { effBeginDt = value; return this; }
            public Builder effEndDt(LocalDateTime value) { effEndDt = value; return this; }
            public Builder histNavInd(String value) { histNavInd = value; return this; }
            public Builder relationshipTypeCd(String value) { relationshipTypeCd = value; return this; }
            public Builder preparesAndPurchasesSw(String value) { preparesAndPurchasesSw = value; return this; }
            public Builder fillsParentalRoleSw(String value) { fillsParentalRoleSw = value; return this; }
            public Builder taxDependentSw(String value) { taxDependentSw = value; return this; }
            public Builder relationshipVrfCd(String value) { relationshipVrfCd = value; return this; }
            public Builder providesCareForSw(String value) { providesCareForSw = value; return this; }
            public Builder physAbleToPurchPrepSw(String value) { physAbleToPurchPrepSw = value; return this; }
            public Builder reportDt(LocalDateTime value) { reportDt = value; return this; }
            public Builder discoveryDt(LocalDateTime value) { discoveryDt = value; return this; }
            public Builder timelySw(String value) { timelySw = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder providesSupportForSw(String value) { providesSupportForSw = value; return this; }
            public Builder marriageDt(LocalDateTime value) { marriageDt = value; return this; }
            public Builder verfReceivedDt(LocalDateTime value) { verfReceivedDt = value; return this; }
            public Builder isCompleteSw(String value) { isCompleteSw = value; return this; }
            public Builder livingTogetherSw(String value) { livingTogetherSw = value; return this; }

            public DcRelationshipsDelta build() {
                return new DcRelationshipsDelta(indvId, refIndvId, historySeq, createUserId, updateUserId, createDt,
                        updateDt, uniqueTransId, effBeginDt, effEndDt, histNavInd, relationshipTypeCd,
                        preparesAndPurchasesSw, fillsParentalRoleSw, taxDependentSw, relationshipVrfCd,
                        providesCareForSw, physAbleToPurchPrepSw, reportDt, discoveryDt, timelySw, archiveDt,
                        providesSupportForSw, marriageDt, verfReceivedDt, isCompleteSw, livingTogetherSw);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_INDV_ADDR")
    public record IndvAddrDelta(LocalDateTime updateDt, @Id BigDecimal indvId, String addrStNum, String addrStNumFrac,
            String addrStNm, String addrAptNum, String addrLine, String addrCity, String addrCountyCd,
            String addrStateCd, String addrZip5, String addrZip4, BigDecimal caseNum, String addrDwellingTypeCd,
            String addrStTypeCd, LocalDateTime effBeginDt, LocalDateTime effEndDt, BigDecimal edgNum,
            String etlMappingName, String addrTypeCd, LocalDateTime loadDate, LocalDateTime createDt,
            String addrStDirCd) {

        /// `IndvAddrDelta.builder().updateDt(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private LocalDateTime updateDt;
            private BigDecimal indvId;
            private String addrStNum;
            private String addrStNumFrac;
            private String addrStNm;
            private String addrAptNum;
            private String addrLine;
            private String addrCity;
            private String addrCountyCd;
            private String addrStateCd;
            private String addrZip5;
            private String addrZip4;
            private BigDecimal caseNum;
            private String addrDwellingTypeCd;
            private String addrStTypeCd;
            private LocalDateTime effBeginDt;
            private LocalDateTime effEndDt;
            private BigDecimal edgNum;
            private String etlMappingName;
            private String addrTypeCd;
            private LocalDateTime loadDate;
            private LocalDateTime createDt;
            private String addrStDirCd;

            private Builder() {}

            public Builder updateDt(LocalDateTime value) { updateDt = value; return this; }
            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder addrStNum(String value) { addrStNum = value; return this; }
            public Builder addrStNumFrac(String value) { addrStNumFrac = value; return this; }
            public Builder addrStNm(String value) { addrStNm = value; return this; }
            public Builder addrAptNum(String value) { addrAptNum = value; return this; }
            public Builder addrLine(String value) { addrLine = value; return this; }
            public Builder addrCity(String value) { addrCity = value; return this; }
            public Builder addrCountyCd(String value) { addrCountyCd = value; return this; }
            public Builder addrStateCd(String value) { addrStateCd = value; return this; }
            public Builder addrZip5(String value) { addrZip5 = value; return this; }
            public Builder addrZip4(String value) { addrZip4 = value; return this; }
            public Builder caseNum(BigDecimal value) { caseNum = value; return this; }
            public Builder addrDwellingTypeCd(String value) { addrDwellingTypeCd = value; return this; }
            public Builder addrStTypeCd(String value) { addrStTypeCd = value; return this; }
            public Builder effBeginDt(LocalDateTime value) { effBeginDt = value; return this; }
            public Builder effEndDt(LocalDateTime value) { effEndDt = value; return this; }
            public Builder edgNum(BigDecimal value) { edgNum = value; return this; }
            public Builder etlMappingName(String value) { etlMappingName = value; return this; }
            public Builder addrTypeCd(String value) { addrTypeCd = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder addrStDirCd(String value) { addrStDirCd = value; return this; }

            public IndvAddrDelta build() {
                return new IndvAddrDelta(updateDt, indvId, addrStNum, addrStNumFrac, addrStNm, addrAptNum, addrLine,
                        addrCity, addrCountyCd, addrStateCd, addrZip5, addrZip4, caseNum, addrDwellingTypeCd,
                        addrStTypeCd, effBeginDt, effEndDt, edgNum, etlMappingName, addrTypeCd, loadDate, createDt,
                        addrStDirCd);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_D_IN_MANAGED_CARE")
    public record InManagedCareDelta(@Id BigDecimal indvId, String mcProgCode, LocalDateTime beginDt, BigDecimal historySeq,
            String mcEligCode, String mcCandidateFlag, String mcPlan, String mcStatusCd, String mcEventCd,
            LocalDateTime mcEventDt, BigDecimal uniqueTransId, String createUserId, LocalDateTime createDt,
            String providerNum, LocalDateTime endDt, LocalDateTime archiveDt, String mcCountyCd,
            LocalDateTime estimatedEligEndDt, String voluntarySw, String mergeSeparateInd, BigDecimal realIndvId,
            String waiverSw, String mmpCandidateFlag, LocalDateTime loadDate) {

        /// `InManagedCareDelta.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private String mcProgCode;
            private LocalDateTime beginDt;
            private BigDecimal historySeq;
            private String mcEligCode;
            private String mcCandidateFlag;
            private String mcPlan;
            private String mcStatusCd;
            private String mcEventCd;
            private LocalDateTime mcEventDt;
            private BigDecimal uniqueTransId;
            private String createUserId;
            private LocalDateTime createDt;
            private String providerNum;
            private LocalDateTime endDt;
            private LocalDateTime archiveDt;
            private String mcCountyCd;
            private LocalDateTime estimatedEligEndDt;
            private String voluntarySw;
            private String mergeSeparateInd;
            private BigDecimal realIndvId;
            private String waiverSw;
            private String mmpCandidateFlag;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder mcProgCode(String value) { mcProgCode = value; return this; }
            public Builder beginDt(LocalDateTime value) { beginDt = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder mcEligCode(String value) { mcEligCode = value; return this; }
            public Builder mcCandidateFlag(String value) { mcCandidateFlag = value; return this; }
            public Builder mcPlan(String value) { mcPlan = value; return this; }
            public Builder mcStatusCd(String value) { mcStatusCd = value; return this; }
            public Builder mcEventCd(String value) { mcEventCd = value; return this; }
            public Builder mcEventDt(LocalDateTime value) { mcEventDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder providerNum(String value) { providerNum = value; return this; }
            public Builder endDt(LocalDateTime value) { endDt = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder mcCountyCd(String value) { mcCountyCd = value; return this; }
            public Builder estimatedEligEndDt(LocalDateTime value) { estimatedEligEndDt = value; return this; }
            public Builder voluntarySw(String value) { voluntarySw = value; return this; }
            public Builder mergeSeparateInd(String value) { mergeSeparateInd = value; return this; }
            public Builder realIndvId(BigDecimal value) { realIndvId = value; return this; }
            public Builder waiverSw(String value) { waiverSw = value; return this; }
            public Builder mmpCandidateFlag(String value) { mmpCandidateFlag = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public InManagedCareDelta build() {
                return new InManagedCareDelta(indvId, mcProgCode, beginDt, historySeq, mcEligCode, mcCandidateFlag,
                        mcPlan, mcStatusCd, mcEventCd, mcEventDt, uniqueTransId, createUserId, createDt, providerNum,
                        endDt, archiveDt, mcCountyCd, estimatedEligEndDt, voluntarySw, mergeSeparateInd, realIndvId,
                        waiverSw, mmpCandidateFlag, loadDate);
            }
        }
    }

    /// Provisional `@Id` `INDV_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_TRS_H_DC_INDV")
    public record DcIndvHist(@Id BigDecimal indvId, BigDecimal historySeq, String createUserId, LocalDateTime createDt,
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
            String typeOfConservatorshipCd, String tribeName, LocalDateTime loadDate) {

        /// `DcIndvHist.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private BigDecimal indvId;
            private BigDecimal historySeq;
            private String createUserId;
            private LocalDateTime createDt;
            private BigDecimal uniqueTransId;
            private BigDecimal ssn;
            private LocalDateTime dobDt;
            private String lastName;
            private String firstName;
            private String sufxName;
            private String prefixName;
            private String midName;
            private String dobVrfCd;
            private String raceCd;
            private String ssaValidationSw;
            private String ssnVrfCd;
            private String ethnicityCd;
            private String genderCd;
            private String inactiveInd;
            private BigDecimal empId;
            private String fileClearanceSw;
            private BigDecimal chipSeqNum;
            private String mergeSeparateInd;
            private LocalDateTime deathDt;
            private String deceasedDtVrfCd;
            private String highneedProfileSw;
            private String highneedCriteriaCd;
            private String mhmrCaseNum;
            private LocalDateTime archiveDt;
            private String deleteSw;
            private String fedRcgnzdIndianTribeSw;
            private String splHealthCareEnrolledSw;
            private String inFcOn18thBirthdaySw;
            private String inFcOn18thBrthdatVrfCd;
            private String stateCd;
            private BigDecimal dfpsPersonId;
            private String maidenName;
            private String mothersMaidenName;
            private String isCompleteSw;
            private String otherRace;
            private String inactivateTypeCd;
            private String potentialDuplicateSw;
            private String potentialDuplicateTypeCd;
            private LocalDateTime inactivatedDt;
            private String inactivatedByUserId;
            private LocalDateTime potentialDuplicateDt;
            private String potentialDuplicateUserId;
            private BigDecimal potentialDupPrimaryId;
            private BigDecimal mergeRequestSeqNum;
            private BigDecimal mergeUniqueTransId;
            private String indTrbVrfCd;
            private LocalDateTime wtpyResDueDt;
            private LocalDateTime wtpyResEndDt;
            private String typeOfConservatorshipCd;
            private String tribeName;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder indvId(BigDecimal value) { indvId = value; return this; }
            public Builder historySeq(BigDecimal value) { historySeq = value; return this; }
            public Builder createUserId(String value) { createUserId = value; return this; }
            public Builder createDt(LocalDateTime value) { createDt = value; return this; }
            public Builder uniqueTransId(BigDecimal value) { uniqueTransId = value; return this; }
            public Builder ssn(BigDecimal value) { ssn = value; return this; }
            public Builder dobDt(LocalDateTime value) { dobDt = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder sufxName(String value) { sufxName = value; return this; }
            public Builder prefixName(String value) { prefixName = value; return this; }
            public Builder midName(String value) { midName = value; return this; }
            public Builder dobVrfCd(String value) { dobVrfCd = value; return this; }
            public Builder raceCd(String value) { raceCd = value; return this; }
            public Builder ssaValidationSw(String value) { ssaValidationSw = value; return this; }
            public Builder ssnVrfCd(String value) { ssnVrfCd = value; return this; }
            public Builder ethnicityCd(String value) { ethnicityCd = value; return this; }
            public Builder genderCd(String value) { genderCd = value; return this; }
            public Builder inactiveInd(String value) { inactiveInd = value; return this; }
            public Builder empId(BigDecimal value) { empId = value; return this; }
            public Builder fileClearanceSw(String value) { fileClearanceSw = value; return this; }
            public Builder chipSeqNum(BigDecimal value) { chipSeqNum = value; return this; }
            public Builder mergeSeparateInd(String value) { mergeSeparateInd = value; return this; }
            public Builder deathDt(LocalDateTime value) { deathDt = value; return this; }
            public Builder deceasedDtVrfCd(String value) { deceasedDtVrfCd = value; return this; }
            public Builder highneedProfileSw(String value) { highneedProfileSw = value; return this; }
            public Builder highneedCriteriaCd(String value) { highneedCriteriaCd = value; return this; }
            public Builder mhmrCaseNum(String value) { mhmrCaseNum = value; return this; }
            public Builder archiveDt(LocalDateTime value) { archiveDt = value; return this; }
            public Builder deleteSw(String value) { deleteSw = value; return this; }
            public Builder fedRcgnzdIndianTribeSw(String value) { fedRcgnzdIndianTribeSw = value; return this; }
            public Builder splHealthCareEnrolledSw(String value) { splHealthCareEnrolledSw = value; return this; }
            public Builder inFcOn18thBirthdaySw(String value) { inFcOn18thBirthdaySw = value; return this; }
            public Builder inFcOn18thBrthdatVrfCd(String value) { inFcOn18thBrthdatVrfCd = value; return this; }
            public Builder stateCd(String value) { stateCd = value; return this; }
            public Builder dfpsPersonId(BigDecimal value) { dfpsPersonId = value; return this; }
            public Builder maidenName(String value) { maidenName = value; return this; }
            public Builder mothersMaidenName(String value) { mothersMaidenName = value; return this; }
            public Builder isCompleteSw(String value) { isCompleteSw = value; return this; }
            public Builder otherRace(String value) { otherRace = value; return this; }
            public Builder inactivateTypeCd(String value) { inactivateTypeCd = value; return this; }
            public Builder potentialDuplicateSw(String value) { potentialDuplicateSw = value; return this; }
            public Builder potentialDuplicateTypeCd(String value) { potentialDuplicateTypeCd = value; return this; }
            public Builder inactivatedDt(LocalDateTime value) { inactivatedDt = value; return this; }
            public Builder inactivatedByUserId(String value) { inactivatedByUserId = value; return this; }
            public Builder potentialDuplicateDt(LocalDateTime value) { potentialDuplicateDt = value; return this; }
            public Builder potentialDuplicateUserId(String value) { potentialDuplicateUserId = value; return this; }
            public Builder potentialDupPrimaryId(BigDecimal value) { potentialDupPrimaryId = value; return this; }
            public Builder mergeRequestSeqNum(BigDecimal value) { mergeRequestSeqNum = value; return this; }
            public Builder mergeUniqueTransId(BigDecimal value) { mergeUniqueTransId = value; return this; }
            public Builder indTrbVrfCd(String value) { indTrbVrfCd = value; return this; }
            public Builder wtpyResDueDt(LocalDateTime value) { wtpyResDueDt = value; return this; }
            public Builder wtpyResEndDt(LocalDateTime value) { wtpyResEndDt = value; return this; }
            public Builder typeOfConservatorshipCd(String value) { typeOfConservatorshipCd = value; return this; }
            public Builder tribeName(String value) { tribeName = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public DcIndvHist build() {
                return new DcIndvHist(indvId, historySeq, createUserId, createDt, uniqueTransId, ssn, dobDt, lastName,
                        firstName, sufxName, prefixName, midName, dobVrfCd, raceCd, ssaValidationSw, ssnVrfCd,
                        ethnicityCd, genderCd, inactiveInd, empId, fileClearanceSw, chipSeqNum, mergeSeparateInd,
                        deathDt, deceasedDtVrfCd, highneedProfileSw, highneedCriteriaCd, mhmrCaseNum, archiveDt,
                        deleteSw, fedRcgnzdIndianTribeSw, splHealthCareEnrolledSw, inFcOn18thBirthdaySw,
                        inFcOn18thBrthdatVrfCd, stateCd, dfpsPersonId, maidenName, mothersMaidenName, isCompleteSw,
                        otherRace, inactivateTypeCd, potentialDuplicateSw, potentialDuplicateTypeCd, inactivatedDt,
                        inactivatedByUserId, potentialDuplicateDt, potentialDuplicateUserId, potentialDupPrimaryId,
                        mergeRequestSeqNum, mergeUniqueTransId, indTrbVrfCd, wtpyResDueDt, wtpyResEndDt,
                        typeOfConservatorshipCd, tribeName, loadDate);
            }
        }
    }

    /// `STG_TRS_VALID_MEMBERS`: registry of member source keys accepted by `m_Tgt_C_S_TRS_Pty_OnGoing`; every other
    /// TRS mapping joins to it.
    @Table("STG_TRS_VALID_MEMBERS")
    public record ValidMember(Long indvId, @Id String ptyPk, String srcTbl, LocalDateTime createDate) {

        /// `ValidMember.builder().indvId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Long indvId;
            private String ptyPk;
            private String srcTbl;
            private LocalDateTime createDate;

            private Builder() {}

            public Builder indvId(Long value) { indvId = value; return this; }
            public Builder ptyPk(String value) { ptyPk = value; return this; }
            public Builder srcTbl(String value) { srcTbl = value; return this; }
            public Builder createDate(LocalDateTime value) { createDate = value; return this; }

            public ValidMember build() {
                return new ValidMember(indvId, ptyPk, srcTbl, createDate);
            }
        }
    }

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
            String srcPstlCdExt) {

        /// `UniqueAddressDelta.builder().addrId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String addrId;
            private String addrLn1;
            private String addrLn2;
            private String bldngNm;
            private String flrNum;
            private String city;
            private String county;
            private String state;
            private String cntryCd;
            private String pstlCd;
            private String pstlCdExt;
            private BigDecimal lattd;
            private BigDecimal lngtd;
            private String vldtnMsg;
            private String vldtnDesc;
            private String mlbltyScr;
            private String addrTpCd;
            private String orgDesc;
            private String orgDept;
            private String orgNm;
            private String bldgNmbr;
            private String subBldgNm;
            private String subBldgDesc;
            private String geocdStsCd;
            private String rsdntlDlvryInd;
            private BigDecimal addrdrRsltPct;
            private String erlyWrngCd;
            private String cassErrCd;
            private String dlvryPntVldn;
            private String srcAddrLn1;
            private String srcAddrLn2;
            private String srcCity;
            private String srcCounty;
            private String srcState;
            private String srcCntry;
            private String srcPstlCd;
            private String srcPstlCdExt;

            private Builder() {}

            public Builder addrId(String value) { addrId = value; return this; }
            public Builder addrLn1(String value) { addrLn1 = value; return this; }
            public Builder addrLn2(String value) { addrLn2 = value; return this; }
            public Builder bldngNm(String value) { bldngNm = value; return this; }
            public Builder flrNum(String value) { flrNum = value; return this; }
            public Builder city(String value) { city = value; return this; }
            public Builder county(String value) { county = value; return this; }
            public Builder state(String value) { state = value; return this; }
            public Builder cntryCd(String value) { cntryCd = value; return this; }
            public Builder pstlCd(String value) { pstlCd = value; return this; }
            public Builder pstlCdExt(String value) { pstlCdExt = value; return this; }
            public Builder lattd(BigDecimal value) { lattd = value; return this; }
            public Builder lngtd(BigDecimal value) { lngtd = value; return this; }
            public Builder vldtnMsg(String value) { vldtnMsg = value; return this; }
            public Builder vldtnDesc(String value) { vldtnDesc = value; return this; }
            public Builder mlbltyScr(String value) { mlbltyScr = value; return this; }
            public Builder addrTpCd(String value) { addrTpCd = value; return this; }
            public Builder orgDesc(String value) { orgDesc = value; return this; }
            public Builder orgDept(String value) { orgDept = value; return this; }
            public Builder orgNm(String value) { orgNm = value; return this; }
            public Builder bldgNmbr(String value) { bldgNmbr = value; return this; }
            public Builder subBldgNm(String value) { subBldgNm = value; return this; }
            public Builder subBldgDesc(String value) { subBldgDesc = value; return this; }
            public Builder geocdStsCd(String value) { geocdStsCd = value; return this; }
            public Builder rsdntlDlvryInd(String value) { rsdntlDlvryInd = value; return this; }
            public Builder addrdrRsltPct(BigDecimal value) { addrdrRsltPct = value; return this; }
            public Builder erlyWrngCd(String value) { erlyWrngCd = value; return this; }
            public Builder cassErrCd(String value) { cassErrCd = value; return this; }
            public Builder dlvryPntVldn(String value) { dlvryPntVldn = value; return this; }
            public Builder srcAddrLn1(String value) { srcAddrLn1 = value; return this; }
            public Builder srcAddrLn2(String value) { srcAddrLn2 = value; return this; }
            public Builder srcCity(String value) { srcCity = value; return this; }
            public Builder srcCounty(String value) { srcCounty = value; return this; }
            public Builder srcState(String value) { srcState = value; return this; }
            public Builder srcCntry(String value) { srcCntry = value; return this; }
            public Builder srcPstlCd(String value) { srcPstlCd = value; return this; }
            public Builder srcPstlCdExt(String value) { srcPstlCdExt = value; return this; }

            public UniqueAddressDelta build() {
                return new UniqueAddressDelta(addrId, addrLn1, addrLn2, bldngNm, flrNum, city, county, state, cntryCd,
                        pstlCd, pstlCdExt, lattd, lngtd, vldtnMsg, vldtnDesc, mlbltyScr, addrTpCd, orgDesc, orgDept,
                        orgNm, bldgNmbr, subBldgNm, subBldgDesc, geocdStsCd, rsdntlDlvryInd, addrdrRsltPct, erlyWrngCd,
                        cassErrCd, dlvryPntVldn, srcAddrLn1, srcAddrLn2, srcCity, srcCounty, srcState, srcCntry,
                        srcPstlCd, srcPstlCdExt);
            }
        }
    }
}
