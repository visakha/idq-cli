package com.idq.cli.source.fss;

import com.idq.cli.core.reference.LookupRows.KeyNumber;
import com.idq.cli.core.reference.LookupRows.KeyValue;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// Named-query interface of the FSS workflow (`wf_FSS_Stage_Load`). All mappings read the source view
/// `V_FSS_ETL_SRC` (client and registration rows); the IDQ source filters are applied in SQL.
public interface FssQueries extends Repository<FssTargets.InactiveStatus, String> {

    /// [docs/mappings/019_m_Tgt_C_S_FSS_Pty_Validation.md#fss-019-active-and-inactive-clients]
    record ClientName(String sourceType, Long idClient, String ptySrcKey, String nmFirst, String nmLast,
            String nmMiddle, LocalDateTime dtDob, LocalDateTime dtLastUpdate, LocalDateTime stgUpdateDate,
            String clientDtlCapxaction, String lastInactvClientYn) {}

    @Query("""
            SELECT source_type, id_client, pty_src_key, nm_first, nm_last, nm_middle, dt_dob, dt_last_update,
                   stg_update_date, client_dtl__capxaction AS client_dtl_capxaction, last_inactv_client_yn
            FROM v_fss_etl_src
            WHERE last_active_client_registration_yn = 'Y' OR last_inactv_client_yn = 'Y'
            """)
    List<ClientName> fetchClientNames();

    /// [docs/mappings/020_m_Tgt_C_S_FSS_Pty.md#fss-020-client-demographics]
    record ClientDemographics(String sourceType, LocalDateTime dtLastUpdate, Long idClient, String ptySrcKey,
            String nmFirst, String nmLast, String nmMiddle, LocalDateTime dtDob, String cdGender, String languageCd,
            String cdHispanic, Integer raceWhite, Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn,
            String cdSuffix) {}

    @Query("""
            SELECT source_type, dt_last_update, id_client, pty_src_key, nm_first, nm_last, nm_middle, dt_dob,
                   cd_gender, language_cd, cd_hispanic, race_white, race_aa, race_asian, race_pi, race_an, cd_suffix
            FROM v_fss_etl_src
            WHERE last_active_client_registration_yn = 'Y'
            """)
    List<ClientDemographics> fetchClientDemographics();

    /// [docs/mappings/021_m_Tgt_C_S_FSS_Pty_Addr.md#fss-021-registration-addresses]
    record ClientAddress(String sourceType, Long idClient, Long idRegistrationClient, String ptySrcKey,
            String addrLine1, String addrLine2, String addrCity, String cdCnty, String addrState, String addrZip,
            LocalDateTime dtCreated, LocalDateTime dtLastUpdate) {}

    @Query("""
            SELECT source_type, id_client, id_registration_client, pty_src_key, addr_line1, addr_line2, addr_city,
                   cd_cnty, addr_state, addr_zip, dt_created, dt_last_update
            FROM v_fss_etl_src
            WHERE dtl__capxaction <> 'D'
            """)
    List<ClientAddress> fetchClientAddresses();

    /// [docs/mappings/022_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md#fss-022-client-and-registration-ids]
    record ClientIdentifier(Long idClient, LocalDateTime dtCreated, LocalDateTime dtLastUpdate, String ptySrcKey,
            String sourceType) {}

    @Query("""
            SELECT id_client, dt_created, dt_last_update, pty_src_key, source_type
            FROM v_fss_etl_src
            WHERE last_active_client_registration_yn = 'Y'
            """)
    List<ClientIdentifier> fetchClientIdentifiers();

    /// [docs/mappings/023_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md#fss-023-registration-phone-and-e-mail]
    record ClientContact(Long idRegistrationClient, LocalDateTime dtLastUpdate, String nbrPhone, String addrEmail,
            String sourceType, String ptySrcKey, String nbrPhoneExt) {}

    @Query("""
            SELECT id_registration_client, dt_last_update, nbr_phone, addr_email, source_type, pty_src_key,
                   nbr_phone_ext
            FROM v_fss_etl_src
            WHERE dtl__capxaction <> 'D'
            """)
    List<ClientContact> fetchClientContacts();

    /// [docs/mappings/024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md#fss-024-client-relations]
    record ClientRelation(String relationDirection, Long relnIdClient, String relnCdGender, Long idClient,
            String ptySrcKey, String relnPtySrcKey, LocalDateTime relnDtLastUpdate, LocalDateTime relnDtCreated,
            String cdReltshpToTc, String cdGender, Long idRegistration) {}

    @Query("""
            SELECT relation_direction, reln_id_client, reln_cd_gender, id_client, pty_src_key, reln_pty_src_key,
                   reln_dt_last_update, reln_dt_created, cd_reltshp_to_tc, cd_gender, id_registration
            FROM v_fss_etl_src_relations
            """)
    List<ClientRelation> fetchClientRelations();

    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_fss_pty_inactive_sts
            WHERE rowid_system = 'FSS' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

    @Query("""
            SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
            WHERE rowid_system = 'FSS'
            """)
    List<KeyNumber> fetchHubStates();
}
