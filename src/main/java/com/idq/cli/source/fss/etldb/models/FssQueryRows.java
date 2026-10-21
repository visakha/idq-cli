package com.idq.cli.source.fss.etldb.models;

import java.time.LocalDateTime;

/// Result rows of the FSS `IdqMapInitQuery`s and lookups. They are projections, not tables: each is returned
/// by a `@Query` method of the repository of the table it is read from (`source.fss.etldb.repo`).
public final class FssQueryRows {

    private FssQueryRows() {}

    /// [docs/mappings/019_m_Tgt_C_S_FSS_Pty_Validation.md#fss-019-active-and-inactive-clients]
    public record ClientName(String sourceType, Long idClient, String ptySrcKey, String nmFirst, String nmLast,
            String nmMiddle, LocalDateTime dtDob, LocalDateTime dtLastUpdate, LocalDateTime stgUpdateDate,
            String clientDtlCapxaction, String lastInactvClientYn) {}

    /// [docs/mappings/020_m_Tgt_C_S_FSS_Pty.md#fss-020-client-demographics]
    public record ClientDemographics(String sourceType, LocalDateTime dtLastUpdate, Long idClient, String ptySrcKey,
            String nmFirst, String nmLast, String nmMiddle, LocalDateTime dtDob, String cdGender, String languageCd,
            String cdHispanic, Integer raceWhite, Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn,
            String cdSuffix) {}

    /// [docs/mappings/021_m_Tgt_C_S_FSS_Pty_Addr.md#fss-021-registration-addresses]
    public record ClientAddress(String sourceType, Long idClient, Long idRegistrationClient, String ptySrcKey,
            String addrLine1, String addrLine2, String addrCity, String cdCnty, String addrState, String addrZip,
            LocalDateTime dtCreated, LocalDateTime dtLastUpdate) {}

    /// [docs/mappings/022_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md#fss-022-client-and-registration-ids]
    public record ClientIdentifier(Long idClient, LocalDateTime dtCreated, LocalDateTime dtLastUpdate, String ptySrcKey,
            String sourceType) {}

    /// [docs/mappings/023_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md#fss-023-registration-phone-and-e-mail]
    public record ClientContact(Long idRegistrationClient, LocalDateTime dtLastUpdate, String nbrPhone,
            String addrEmail, String sourceType, String ptySrcKey, String nbrPhoneExt) {}

    /// [docs/mappings/024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md#fss-024-client-relations]
    public record ClientRelation(String relationDirection, Long relnIdClient, String relnCdGender, Long idClient,
            String ptySrcKey, String relnPtySrcKey, LocalDateTime relnDtLastUpdate, LocalDateTime relnDtCreated,
            String cdReltshpToTc, String cdGender, Long idRegistration) {}
}
