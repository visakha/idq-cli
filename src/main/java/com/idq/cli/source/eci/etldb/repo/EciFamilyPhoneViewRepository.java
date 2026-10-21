package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyContact;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_ECI_ETL_SRC_FAMILY_PHONE` - child and family phones and e-mail addresses.
public interface EciFamilyPhoneViewRepository extends Repository<EciSources.EtlSrcFamilyPhone, String> {

    /// `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`.
    @Query("""
            SELECT source_table, id_family_phone, id_case, id, period_start_date, phone_email_type, phone_email,
                   work_ext, phone_tp, usg_tp, pref_lvl
            FROM v_eci_etl_src_family_phone
            """)
    List<FamilyContact> fetchFamilyContacts();
}
