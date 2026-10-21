package com.idq.cli.source.wic.etldb.repo;

import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientDemographics;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientIdentifier;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientName;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyAddress;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyContact;
import com.idq.cli.source.wic.etldb.models.WicSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_WIC_ETL_SRC` - client and family rows, read by every WIC mapping.
public interface WicEtlSrcViewRepository extends Repository<WicSources.EtlSrc, String> {

    /// `m_Tgt_C_S_WIC_Pty_Validation`: the `IdqMapInitQuery`.
    @Query("""
            SELECT id, first_name, last_name, middle_name, datekey, load_date, source_table, pty_src_key, dob
            FROM v_wic_etl_src
            """)
    List<ClientName> fetchClientNames();

    /// `m_Tgt_C_S_WIC_Pty`: the `IdqMapInitQuery`.
    @Query("""
            SELECT source_table, datekey, load_date, id, pty_src_key, first_name, last_name, middle_name, dob, gender,
                   birth_wt_lb, birth_wt_oz, language_cd, ethnicity, race_white_ind, race_aa_ind, race_asian_ind,
                   race_pi_ind, race_an_ind
            FROM v_wic_etl_src
            """)
    List<ClientDemographics> fetchClientDemographics();

    /// `m_Tgt_C_S_WIC_Pty_Addr`: the `IdqMapInitQuery`.
    @Query("""
            SELECT source_table, id, fid, pty_src_key, address1, address2, city, county, zip_code,
                   date_address_valid_from
            FROM v_wic_etl_src
            """)
    List<FamilyAddress> fetchFamilyAddresses();

    /// `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`: the `IdqMapInitQuery`.
    @Query("SELECT id, datekey, pty_src_key, source_table FROM v_wic_etl_src")
    List<ClientIdentifier> fetchClientIdentifiers();

    /// `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`: the `IdqMapInitQuery`.
    @Query("SELECT fid, datekey, phone, email, source_table, pty_src_key, id FROM v_wic_etl_src")
    List<FamilyContact> fetchFamilyContacts();
}
