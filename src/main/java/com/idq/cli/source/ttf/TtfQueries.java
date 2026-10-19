package com.idq.cli.source.ttf;

import com.idq.cli.core.reference.LookupRows.KeyNumber;
import com.idq.cli.core.reference.LookupRows.KeyValue;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// Named-query interface of the TTF workflow (`wf_TTF_Stage_Load`). Every mapping reads the source view
/// `V_TTF_ETL_SRC`; the hard-coded id lists left in the IDQ source filters for testing are removed.
public interface TtfQueries extends Repository<TtfTargets.InactiveStatus, String> {

    /// [docs/mappings/025_m_Tgt_C_S_TTF_Pty_Validation.md#ttf-025-clients-for-validation]
    record ClientName(Long clientsId, String firstname, String lastname, String middlename,
            LocalDateTime createddate, LocalDateTime dob, LocalDateTime submitdate, String clientExistsFlag) {}

    @Query("""
            SELECT clients_id, firstname, lastname, middlename, createddate, dob, submitdate, client_exists_flag
            FROM v_ttf_etl_src
            """)
    List<ClientName> fetchClientNames();

    /// [docs/mappings/026_m_Tgt_C_S_TTF_Pty.md#ttf-026-client-demographics]
    record ClientDemographics(LocalDateTime submitdate, LocalDateTime loadDate, Long clientsId, String ptySrcKey,
            String firstname, String lastname, String middlename, LocalDateTime dob, String sexid,
            String raceethnicityid) {}

    @Query("""
            SELECT submitdate, load_date, clients_id, pty_src_key, firstname, lastname, middlename, dob,
                   TO_CHAR(sexid) AS sexid, raceethnicityid
            FROM v_ttf_etl_src
            """)
    List<ClientDemographics> fetchClientDemographics();

    /// [docs/mappings/027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md#ttf-027-client-source-key]
    record ClientIdentifier(Long clientsId, LocalDateTime submitdate, String ptySrcKey) {}

    @Query("SELECT clients_id, submitdate, pty_src_key FROM v_ttf_etl_src")
    List<ClientIdentifier> fetchClientIdentifiers();

    /// [docs/mappings/028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md#ttf-028-client-phone]
    record ClientPhone(LocalDateTime submitdate, String phone, String ptySrcKey) {}

    @Query("SELECT submitdate, phone, pty_src_key FROM v_ttf_etl_src")
    List<ClientPhone> fetchClientPhones();

    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_ttf_pty_inactive_sts
            WHERE rowid_system = 'TTF' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

    @Query("""
            SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
            WHERE TRIM(rowid_system) = 'TTF'
            """)
    List<KeyNumber> fetchHubStates();
}
