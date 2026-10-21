package com.idq.cli.source.eci.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/// Result rows of the ECI `IdqMapInitQuery`s and lookups. They are projections, not tables: each is returned by a
/// `@Query` method of the repository of the table it is read from (`source.eci.etldb.repo`).
public final class EciQueryRows {

    private EciQueryRows() {}

    /// [docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md#eci-013-children-and-family-members]
    public record PartyName(String sourceTable, Long id, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, LocalDateTime dateCreated, LocalDateTime dateModified, String modifiedBy,
            String createdBy, LocalDateTime loadDate) {}

    /// [docs/mappings/014_m_Tgt_C_S_ECI_Pty.md#eci-014-child-and-family-demographics]
    public record PartyDemographics(String sourceTable, Long id, String childSsn, String firstName, String lastName,
            String middleInitial, LocalDateTime dob, String gestationAge, String gender, BigDecimal birthWtLb,
            BigDecimal birthWtOz, String interpretInd, String languageCd, String raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, String ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn, LocalDateTime loadDate) {}

    /// [docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md#eci-015-family-addresses]
    public record FamilyAddress(String sourceTable, Long id, Long idFamilyAddress, String address1, String address2,
            String addressCd, String cityName, String countyName, String stateAbbrev, String zipCode, String zipSfx,
            LocalDateTime lastUpdateDate) {}

    /// [docs/mappings/016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md#eci-016-child-and-family-identifiers]
    public record PartyIdentifier(Long id, String ptyRelFk, String srcKeySfx, String altIdTp, String altIdVal,
            LocalDateTime dateCreated, LocalDateTime dateModified, String pkeySrcObject) {}

    /// [docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md#eci-017-family-phones-and-e-mail]
    public record FamilyContact(String sourceTable, String idFamilyPhone, Long idCase, String id,
            LocalDateTime periodStartDate, String phoneEmailType, String phoneEmail, String workExt, String phoneTp,
            String usgTp, String prefLvl) {}

    /// [docs/mappings/018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md#eci-018-child-family-relations]
    public record FamilyRelation(String relationDirection, Long idFamily, String familyGender, Long idChild,
            String familyCd, LocalDateTime dateModified, LocalDateTime dateCreated) {}

    /// `Lookup_V_ECI_ETL_LU_FAMILY_VALIDATION` of the validation mapping.
    public record FamilyValidation(String sourceTable, Long idFamily, String famNameStatus,
            String famPhoneAndAddressSts, String famInactiveSts) {}
}
