package com.idq.cli.source.ttf.etldb.models;

import java.time.LocalDateTime;

/// Result rows of the TTF `IdqMapInitQuery`s and lookups. They are projections, not tables: each is returned
/// by a `@Query` method of the repository of the table it is read from (`source.ttf.etldb.repo`).
public final class TtfQueryRows {

    private TtfQueryRows() {}

    /// [docs/mappings/025_m_Tgt_C_S_TTF_Pty_Validation.md#ttf-025-clients-for-validation]
    public record ClientName(Long clientsId, String firstname, String lastname, String middlename,
            LocalDateTime createddate, LocalDateTime dob, LocalDateTime submitdate, String clientExistsFlag) {}

    /// [docs/mappings/026_m_Tgt_C_S_TTF_Pty.md#ttf-026-client-demographics]
    public record ClientDemographics(LocalDateTime submitdate, LocalDateTime loadDate, Long clientsId, String ptySrcKey,
            String firstname, String lastname, String middlename, LocalDateTime dob, String sexid,
            String raceethnicityid) {}

    /// [docs/mappings/027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md#ttf-027-client-source-key]
    public record ClientIdentifier(Long clientsId, LocalDateTime submitdate, String ptySrcKey) {}

    /// [docs/mappings/028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md#ttf-028-client-phone]
    public record ClientPhone(LocalDateTime submitdate, String phone, String ptySrcKey) {}
}
