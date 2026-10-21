package com.idq.cli.source.eci.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the ECI source tables and views read by
/// `wf_ECI_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [EciQueryRows]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_ECI`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// Tables with the `_D_` (delta detection) infix are named `<Name>Delta`, e.g. `STG_ECI_D_CHILD` is [ChildDelta].
///
/// `STG_ECI_PTY_INACTIVE_STS` is written by the validation mapping: see [EciTargets.InactiveStatus].
public final class EciSources {

    private EciSources() {}

    /// Provisional `@Id` `ID_CHILD`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_D_CHILD")
    public record ChildDelta(@Id Long idChild, String childSsn, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, String gestationAge, String gender, Integer birthWtLb, Integer birthWtOz,
            Integer interpretInd, Integer languageCd, Integer raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, Integer ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn, LocalDateTime loadDate) {}

    /// Provisional `@Id` `ID_FAMILY`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_D_FAMILY")
    public record FamilyDelta(@Id Long idFamily, Long idChild, Integer familyCd, String gender, Integer educationCd,
            Integer employStatusCd, String firstName, String lastName, String middleInitial, LocalDateTime dob,
            Integer childResidesInd, Integer inactiveInd, LocalDateTime dateCreated, LocalDateTime dateModified,
            String modifiedBy, String createdBy, LocalDateTime loadDate) {

        /// `FamilyDelta.builder().lastName("Jacko").gender("M").build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Long idFamily;
            private Long idChild;
            private Integer familyCd;
            private String gender;
            private Integer educationCd;
            private Integer employStatusCd;
            private String firstName;
            private String lastName;
            private String middleInitial;
            private LocalDateTime dob;
            private Integer childResidesInd;
            private Integer inactiveInd;
            private LocalDateTime dateCreated;
            private LocalDateTime dateModified;
            private String modifiedBy;
            private String createdBy;
            private LocalDateTime loadDate;

            private Builder() {}

            public Builder idFamily(Long value) { idFamily = value; return this; }
            public Builder idChild(Long value) { idChild = value; return this; }
            public Builder familyCd(Integer value) { familyCd = value; return this; }
            public Builder gender(String value) { gender = value; return this; }
            public Builder educationCd(Integer value) { educationCd = value; return this; }
            public Builder employStatusCd(Integer value) { employStatusCd = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder middleInitial(String value) { middleInitial = value; return this; }
            public Builder dob(LocalDateTime value) { dob = value; return this; }
            public Builder childResidesInd(Integer value) { childResidesInd = value; return this; }
            public Builder inactiveInd(Integer value) { inactiveInd = value; return this; }
            public Builder dateCreated(LocalDateTime value) { dateCreated = value; return this; }
            public Builder dateModified(LocalDateTime value) { dateModified = value; return this; }
            public Builder modifiedBy(String value) { modifiedBy = value; return this; }
            public Builder createdBy(String value) { createdBy = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }

            public FamilyDelta build() {
                return new FamilyDelta(idFamily, idChild, familyCd, gender, educationCd, employStatusCd, firstName,
                        lastName, middleInitial, dob, childResidesInd, inactiveInd, dateCreated, dateModified,
                        modifiedBy, createdBy, loadDate);
            }
        }
    }

    /// Provisional `@Id` `ID_MEDICAID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("STG_ECI_D_MEDICAID")
    public record MedicaidDelta(@Id Long idMedicaid, Long idCase, String medicaidNbr, LocalDateTime eligDate,
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
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn) {

        /// `SnChild.builder().idChild(42L).gender("F").build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Long idChild;
            private String childSsn;
            private String firstName;
            private String lastName;
            private String middleInitial;
            private LocalDateTime dob;
            private String gestationAge;
            private String gender;
            private Integer birthWtLb;
            private Integer birthWtOz;
            private Integer interpretInd;
            private Integer languageCd;
            private Integer raceCd;
            private LocalDateTime dateCreated;
            private LocalDateTime dateModified;
            private String modifiedBy;
            private String createdBy;
            private Integer ethnicity;
            private Integer raceWhite;
            private Integer raceAa;
            private Integer raceAsian;
            private Integer racePi;
            private Integer raceAn;

            private Builder() {}

            public Builder idChild(Long value) { idChild = value; return this; }
            public Builder childSsn(String value) { childSsn = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder middleInitial(String value) { middleInitial = value; return this; }
            public Builder dob(LocalDateTime value) { dob = value; return this; }
            public Builder gestationAge(String value) { gestationAge = value; return this; }
            public Builder gender(String value) { gender = value; return this; }
            public Builder birthWtLb(Integer value) { birthWtLb = value; return this; }
            public Builder birthWtOz(Integer value) { birthWtOz = value; return this; }
            public Builder interpretInd(Integer value) { interpretInd = value; return this; }
            public Builder languageCd(Integer value) { languageCd = value; return this; }
            public Builder raceCd(Integer value) { raceCd = value; return this; }
            public Builder dateCreated(LocalDateTime value) { dateCreated = value; return this; }
            public Builder dateModified(LocalDateTime value) { dateModified = value; return this; }
            public Builder modifiedBy(String value) { modifiedBy = value; return this; }
            public Builder createdBy(String value) { createdBy = value; return this; }
            public Builder ethnicity(Integer value) { ethnicity = value; return this; }
            public Builder raceWhite(Integer value) { raceWhite = value; return this; }
            public Builder raceAa(Integer value) { raceAa = value; return this; }
            public Builder raceAsian(Integer value) { raceAsian = value; return this; }
            public Builder racePi(Integer value) { racePi = value; return this; }
            public Builder raceAn(Integer value) { raceAn = value; return this; }

            public SnChild build() {
                return new SnChild(idChild, childSsn, firstName, lastName, middleInitial, dob, gestationAge, gender,
                        birthWtLb, birthWtOz, interpretInd, languageCd, raceCd, dateCreated, dateModified, modifiedBy,
                        createdBy, ethnicity, raceWhite, raceAa, raceAsian, racePi, raceAn);
            }
        }
    }

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
