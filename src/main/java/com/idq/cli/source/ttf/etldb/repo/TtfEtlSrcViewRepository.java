package com.idq.cli.source.ttf.etldb.repo;

import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientDemographics;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientIdentifier;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientName;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientPhone;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_TTF_ETL_SRC` - client rows, read by every TTF mapping.
public interface TtfEtlSrcViewRepository extends Repository<TtfSources.EtlSrc, Long> {

    /// `m_Tgt_C_S_TTF_Pty_Validation`: the `IdqMapInitQuery`.
    @Query("""
            SELECT clients_id, firstname, lastname, middlename, createddate, dob, submitdate, client_exists_flag
            FROM v_ttf_etl_src
            """)
    List<ClientName> fetchClientNames();

    /// `m_Tgt_C_S_TTF_Pty`: the `IdqMapInitQuery`.
    @Query("""
            SELECT submitdate, load_date, clients_id, pty_src_key, firstname, lastname, middlename, dob,
                   TO_CHAR(sexid) AS sexid, raceethnicityid
            FROM v_ttf_etl_src
            """)
    List<ClientDemographics> fetchClientDemographics();

    /// `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id`: the `IdqMapInitQuery`.
    @Query("SELECT clients_id, submitdate, pty_src_key FROM v_ttf_etl_src")
    List<ClientIdentifier> fetchClientIdentifiers();

    /// `m_Tgt_C_S_TTF_Pty_Rle_Phn`: the `IdqMapInitQuery`.
    @Query("SELECT submitdate, phone, pty_src_key FROM v_ttf_etl_src")
    List<ClientPhone> fetchClientPhones();
}
