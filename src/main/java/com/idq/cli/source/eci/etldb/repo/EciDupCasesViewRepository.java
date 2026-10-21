package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_ECI_ETL_LU_DUP_CASES` - parties whose every case is a duplicate.
public interface EciDupCasesViewRepository extends Repository<EciSources.EtlLuDupCases, Long> {

    /// `Lookup_V_ECI_ETL_LU_DUP_CASES`, keyed `<source table>|<id>`.
    @Query("SELECT source_table || '|' || id AS lookup_key, TO_CHAR(id) AS lookup_value FROM v_eci_etl_lu_dup_cases")
    List<KeyValue> fetchDuplicateCases();
}
