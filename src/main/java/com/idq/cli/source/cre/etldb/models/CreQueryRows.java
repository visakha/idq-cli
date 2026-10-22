package com.idq.cli.source.cre.etldb.models;

import java.time.LocalDateTime;

/// Result rows of the CRE `IdqMapInitQuery` and lookups. They are projections, not tables: each is returned by a
/// `@Query` method of the repository of the table it is read from (`source.cre.etldb.repo`).
public final class CreQueryRows {

    private CreQueryRows() {}

    /// [docs/mappings/034_m_Tgt_C_S_CRE_CARE_Clients.md#cre-034-care-clients]
    ///
    /// `REC_TYPE`: `I` a client of the delta, `D` a deleted case (`CASEDEL`), `B` the source and `A` the target of a
    /// case move (`CASEMOV`).
    public record CareClient(String careId, LocalDateTime careLastupDt, String firstnm, String lastnm,
            String lastSuf, LocalDateTime birthDt, String sex, String street, String city, String cnty, String state,
            String zip, String zipsuf, String phone, String recipNo, String maintFlag, String ssn,
            LocalDateTime insertDate, String fedeth, String race, String sourceId, String targetId, String rec,
            String recType) {}

    /// `LKP_XREF_SRC` / `LKP_XREF_TGT`: the CRE cross-reference of a CARE id.
    public record PartyXref(String pkeySrcObject, String rowidObject, String origRowidObject) {}
}
