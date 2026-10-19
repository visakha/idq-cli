package com.idq.cli.source.eci;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the ECI source tables and views read by
/// `wf_ECI_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [EciQueries]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_ECI`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// `STG_ECI_PTY_INACTIVE_STS` is written by the validation mapping: see [EciTargets.InactiveStatus].
public final class EciSources {

    private EciSources() {}

    /// Provisional `@Id` `ID_CHILD`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_D_CHILD")
    public record DChild(@Id Long idChild, String childSsn, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, String gestationAge, String gender, Integer birthWtLb, Integer birthWtOz,
            Integer interpretInd, Integer languageCd, Integer raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, Integer ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn, LocalDateTime loadDate) {}

    /// Provisional `@Id` `ID_FAMILY`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_D_FAMILY")
    public record DFamily(@Id Long idFamily, Long idChild, Integer familyCd, String gender, Integer educationCd,
            Integer employStatusCd, String firstName, String lastName, String middleInitial, LocalDateTime dob,
            Integer childResidesInd, Integer inactiveInd, LocalDateTime dateCreated, LocalDateTime dateModified,
            String modifiedBy, String createdBy, LocalDateTime loadDate) {}

    /// Provisional `@Id` `ID_MEDICAID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_D_MEDICAID")
    public record DMedicaid(@Id Long idMedicaid, Long idCase, String medicaidNbr, LocalDateTime eligDate,
            LocalDateTime endDate, Integer currentInd, LocalDateTime cancelDate, String hmoDesc,
            LocalDateTime dateCreated, LocalDateTime dateModified, String modifiedBy, String createdBy,
            Integer consentToBill, LocalDateTime loadDate) {}

    /// Provisional `@Id` `ID_CASE`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_SN_CASE")
    public record SnCase(@Id Long idCase, LocalDateTime dateCreated, LocalDateTime dateModified, Long idChild) {}

    /// Provisional `@Id` `ID_CHILD`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_SN_CHILD")
    public record SnChild(@Id Long idChild, String childSsn, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, String gestationAge, String gender, Integer birthWtLb, Integer birthWtOz,
            Integer interpretInd, Integer languageCd, Integer raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, Integer ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn) {}

    /// Provisional `@Id` `ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_ECI_ETL_LU_DUP_CASES")
    public record EtlLuDupCases(@Id Long id, String sourceTable) {}

    /// Provisional `@Id` `ID_FAMILY`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_ECI_ETL_LU_FAMILY_VALIDATION")
    public record EtlLuFamilyValidation(String famNameStatus, String famPhoneAndAddressSts, String famInactiveSts,
            @Id BigDecimal idFamily, String sourceTable) {}

    /// Provisional `@Id` `ID_FAMILY_ADDRESS`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_ECI_ETL_SRC_FAMILY_ADDRESS")
    public record EtlSrcFamilyAddress(String sourceTable, BigDecimal id, @Id BigDecimal idFamilyAddress,
            String address1, String address2, BigDecimal addressCd, String cityName, String countyName,
            String stateAbbrev, String zipCode, String zipSfx, LocalDateTime lastUpdateDate, String addrTp) {}

    /// Provisional `@Id` `ID_FAMILY_PHONE`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_ECI_ETL_SRC_FAMILY_PHONE")
    public record EtlSrcFamilyPhone(String sourceTable, @Id String idFamilyPhone, BigDecimal idCase, String id,
            LocalDateTime periodStartDate, String phoneEmailType, String phoneEmail, String workExt, String phoneTp,
            String usgTp, String prefLvl) {}
}
