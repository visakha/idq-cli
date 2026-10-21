package com.idq.cli.source.wic.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/// Result rows of the WIC `IdqMapInitQuery`s and lookups. They are projections, not tables: each is returned
/// by a `@Query` method of the repository of the table it is read from (`source.wic.etldb.repo`).
public final class WicQueryRows {

    private WicQueryRows() {}

    /// [docs/mappings/029_m_Tgt_C_S_WIC_Pty_Validation.md#wic-029-clients-for-validation]
    public record ClientName(String id, String firstName, String lastName, String middleName, LocalDateTime datekey,
            LocalDateTime loadDate, String sourceTable, String ptySrcKey, LocalDateTime dob) {}

    /// [docs/mappings/030_m_Tgt_C_S_WIC_Pty.md#wic-030-client-demographics]
    public record ClientDemographics(String sourceTable, LocalDateTime datekey, LocalDateTime loadDate, String id,
            String ptySrcKey, String firstName, String lastName, String middleName, LocalDateTime dob, String gender,
            BigDecimal birthWtLb, BigDecimal birthWtOz, String languageCd, String ethnicity, Integer raceWhiteInd,
            Integer raceAaInd, Integer raceAsianInd, Integer racePiInd, Integer raceAnInd) {}

    /// [docs/mappings/031_m_Tgt_C_S_WIC_Pty_Addr.md#wic-031-family-addresses]
    public record FamilyAddress(String sourceTable, String id, String fid, String ptySrcKey, String address1,
            String address2, String city, String county, String zipCode, LocalDateTime dateAddressValidFrom) {}

    /// [docs/mappings/032_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md#wic-032-client-and-family-ids]
    public record ClientIdentifier(String id, LocalDateTime datekey, String ptySrcKey, String sourceTable) {}

    /// [docs/mappings/033_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md#wic-033-family-phone-and-e-mail]
    public record FamilyContact(String fid, LocalDateTime datekey, String phone, String email, String sourceTable,
            String ptySrcKey, String id) {}
}
