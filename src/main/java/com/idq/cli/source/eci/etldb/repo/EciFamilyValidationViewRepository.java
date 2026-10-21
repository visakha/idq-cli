package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyValidation;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_ECI_ETL_LU_FAMILY_VALIDATION` - name, contact and inactive flags of family members.
public interface EciFamilyValidationViewRepository
        extends Repository<EciSources.EtlLuFamilyValidation, BigDecimal> {

    /// `Lookup_V_ECI_ETL_LU_FAMILY_VALIDATION`.
    @Query("""
            SELECT source_table, id_family, fam_name_status, fam_phone_and_address_sts, fam_inactive_sts
            FROM v_eci_etl_lu_family_validation
            """)
    List<FamilyValidation> fetchFamilyValidations();
}
