package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientAddress;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientContact;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientDemographics;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientIdentifier;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientName;
import com.idq.cli.source.fss.etldb.models.FssSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_FSS_ETL_SRC` - client and registration rows, read by every FSS mapping.
public interface FssEtlSrcViewRepository extends Repository<FssSources.EtlSrc, Long> {

    /// `m_Tgt_C_S_FSS_Pty_Validation`: the `IdqMapInitQuery`.
    @Query("""
            SELECT source_type, id_client, pty_src_key, nm_first, nm_last, nm_middle, dt_dob, dt_last_update,
                   stg_update_date, client_dtl__capxaction AS client_dtl_capxaction, last_inactv_client_yn
            FROM v_fss_etl_src
            WHERE last_active_client_registration_yn = 'Y' OR last_inactv_client_yn = 'Y'
            """)
    List<ClientName> fetchClientNames();

    /// `m_Tgt_C_S_FSS_Pty`: the `IdqMapInitQuery`.
    @Query("""
            SELECT source_type, dt_last_update, id_client, pty_src_key, nm_first, nm_last, nm_middle, dt_dob,
                   cd_gender, language_cd, cd_hispanic, race_white, race_aa, race_asian, race_pi, race_an, cd_suffix
            FROM v_fss_etl_src
            WHERE last_active_client_registration_yn = 'Y'
            """)
    List<ClientDemographics> fetchClientDemographics();

    /// `m_Tgt_C_S_FSS_Pty_Addr`: the `IdqMapInitQuery`.
    @Query("""
            SELECT source_type, id_client, id_registration_client, pty_src_key, addr_line1, addr_line2, addr_city,
                   cd_cnty, addr_state, addr_zip, dt_created, dt_last_update
            FROM v_fss_etl_src
            WHERE dtl__capxaction <> 'D'
            """)
    List<ClientAddress> fetchClientAddresses();

    /// `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`: the `IdqMapInitQuery`.
    @Query("""
            SELECT id_client, dt_created, dt_last_update, pty_src_key, source_type
            FROM v_fss_etl_src
            WHERE last_active_client_registration_yn = 'Y'
            """)
    List<ClientIdentifier> fetchClientIdentifiers();

    /// `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`: the `IdqMapInitQuery`.
    @Query("""
            SELECT id_registration_client, dt_last_update, nbr_phone, addr_email, source_type, pty_src_key,
                   nbr_phone_ext
            FROM v_fss_etl_src
            WHERE dtl__capxaction <> 'D'
            """)
    List<ClientContact> fetchClientContacts();
}
