package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyAddress;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_ECI_ETL_SRC_FAMILY_ADDRESS` - child and family addresses.
public interface EciFamilyAddressViewRepository extends Repository<EciSources.EtlSrcFamilyAddress, BigDecimal> {

    /// `m_Tgt_C_S_ECI_Pty_Addr`.
    @Query("""
            SELECT source_table, id, id_family_address, address1, address2, address_cd, city_name, county_name,
                   state_abbrev, zip_code, zip_sfx, last_update_date
            FROM v_eci_etl_src_family_address
            """)
    List<FamilyAddress> fetchFamilyAddresses();
}
