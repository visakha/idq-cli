package com.idq.cli.source.eci;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the ECI source tables and views read by
/// `wf_ECI_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [EciQueries]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_ECI`). Source tables have no primary key, so the
/// records carry no `@Id` and are only ever read.
///
/// `STG_ECI_PTY_INACTIVE_STS` is written by the validation mapping: see [EciTargets.InactiveStatus].
public final class EciSources {

    private EciSources() {}

    @Table("STG_ECI_D_CHILD")
    public record DChild(Long idChild, String childSsn, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, String gestationAge, String gender, Integer birthWtLb, Integer birthWtOz,
            Integer interpretInd, Integer languageCd, Integer raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, Integer ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn, LocalDateTime loadDate) {}

    @Table("STG_ECI_D_FAMILY")
    public record DFamily(Long idFamily, Long idChild, Integer familyCd, String gender, Integer educationCd,
            Integer employStatusCd, String firstName, String lastName, String middleInitial, LocalDateTime dob,
            Integer childResidesInd, Integer inactiveInd, LocalDateTime dateCreated, LocalDateTime dateModified,
            String modifiedBy, String createdBy, LocalDateTime loadDate) {}

    @Table("STG_ECI_D_MEDICAID")
    public record DMedicaid(Long idMedicaid, Long idCase, String medicaidNbr, LocalDateTime eligDate,
            LocalDateTime endDate, Integer currentInd, LocalDateTime cancelDate, String hmoDesc,
            LocalDateTime dateCreated, LocalDateTime dateModified, String modifiedBy, String createdBy,
            Integer consentToBill, LocalDateTime loadDate) {}

    @Table("STG_ECI_SN_CASE")
    public record SnCase(Long idCase, LocalDateTime dateCreated, LocalDateTime dateModified, Long idChild) {}

    @Table("STG_ECI_SN_CHILD")
    public record SnChild(Long idChild, String childSsn, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, String gestationAge, String gender, Integer birthWtLb, Integer birthWtOz,
            Integer interpretInd, Integer languageCd, Integer raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, Integer ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn) {}

    @Table("V_ECI_ETL_LU_DUP_CASES")
    public record EtlLuDupCases(Long id, String sourceTable) {}

    @Table("V_ECI_ETL_LU_FAMILY_VALIDATION")
    public record EtlLuFamilyValidation(String famNameStatus, String famPhoneAndAddressSts, String famInactiveSts,
            BigDecimal idFamily, String sourceTable) {}

    @Table("V_ECI_ETL_SRC_FAMILY_ADDRESS")
    public record EtlSrcFamilyAddress(String sourceTable, BigDecimal id, BigDecimal idFamilyAddress, String address1,
            String address2, BigDecimal addressCd, String cityName, String countyName, String stateAbbrev,
            String zipCode, String zipSfx, LocalDateTime lastUpdateDate, String addrTp) {}

    @Table("V_ECI_ETL_SRC_FAMILY_PHONE")
    public record EtlSrcFamilyPhone(String sourceTable, String idFamilyPhone, BigDecimal idCase, String id,
            LocalDateTime periodStartDate, String phoneEmailType, String phoneEmail, String workExt, String phoneTp,
            String usgTp, String prefLvl) {}
}
