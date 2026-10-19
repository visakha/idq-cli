package com.idq.cli.source.wic;

import com.idq.cli.core.reference.LookupRows.KeyNumber;
import com.idq.cli.core.reference.LookupRows.KeyValue;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// Named-query interface of the WIC workflow (`wf_WIC_Stage_Load`). Every mapping reads the source view
/// `V_WIC_ETL_SRC` without a source filter.
public interface WicQueries extends Repository<WicTargets.InactiveStatus, String> {

    /// [docs/mappings/029_m_Tgt_C_S_WIC_Pty_Validation.md#wic-029-clients-for-validation]
    record ClientName(String id, String firstName, String lastName, String middleName, LocalDateTime datekey,
            LocalDateTime loadDate, String sourceTable, String ptySrcKey, LocalDateTime dob) {}

    @Query("""
            SELECT id, first_name, last_name, middle_name, datekey, load_date, source_table, pty_src_key, dob
            FROM v_wic_etl_src
            """)
    List<ClientName> fetchClientNames();

    /// [docs/mappings/030_m_Tgt_C_S_WIC_Pty.md#wic-030-client-demographics]
    record ClientDemographics(String sourceTable, LocalDateTime datekey, LocalDateTime loadDate, String id,
            String ptySrcKey, String firstName, String lastName, String middleName, LocalDateTime dob, String gender,
            BigDecimal birthWtLb, BigDecimal birthWtOz, String languageCd, String ethnicity, Integer raceWhiteInd,
            Integer raceAaInd, Integer raceAsianInd, Integer racePiInd, Integer raceAnInd) {}

    @Query("""
            SELECT source_table, datekey, load_date, id, pty_src_key, first_name, last_name, middle_name, dob, gender,
                   birth_wt_lb, birth_wt_oz, language_cd, ethnicity, race_white_ind, race_aa_ind, race_asian_ind,
                   race_pi_ind, race_an_ind
            FROM v_wic_etl_src
            """)
    List<ClientDemographics> fetchClientDemographics();

    /// [docs/mappings/031_m_Tgt_C_S_WIC_Pty_Addr.md#wic-031-family-addresses]
    record FamilyAddress(String sourceTable, String id, String fid, String ptySrcKey, String address1,
            String address2, String city, String county, String zipCode, LocalDateTime dateAddressValidFrom) {}

    @Query("""
            SELECT source_table, id, fid, pty_src_key, address1, address2, city, county, zip_code,
                   date_address_valid_from
            FROM v_wic_etl_src
            """)
    List<FamilyAddress> fetchFamilyAddresses();

    /// [docs/mappings/032_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md#wic-032-client-and-family-ids]
    record ClientIdentifier(String id, LocalDateTime datekey, String ptySrcKey, String sourceTable) {}

    @Query("SELECT id, datekey, pty_src_key, source_table FROM v_wic_etl_src")
    List<ClientIdentifier> fetchClientIdentifiers();

    /// [docs/mappings/033_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md#wic-033-family-phone-and-e-mail]
    record FamilyContact(String fid, LocalDateTime datekey, String phone, String email, String sourceTable,
            String ptySrcKey, String id) {}

    @Query("SELECT fid, datekey, phone, email, source_table, pty_src_key, id FROM v_wic_etl_src")
    List<FamilyContact> fetchFamilyContacts();

    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_wic_pty_inactive_sts
            WHERE rowid_system = 'WIC' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

    @Query("""
            SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
            WHERE rowid_system = 'WIC'
            """)
    List<KeyNumber> fetchHubStates();
}
