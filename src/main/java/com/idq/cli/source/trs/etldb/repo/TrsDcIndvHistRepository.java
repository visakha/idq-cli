package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.ValidSsn;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_H_DC_INDV` - individual history.
public interface TrsDcIndvHistRepository extends Repository<TrsSources.DcIndvHist, BigDecimal> {

    /// SSNs validated by the SSA.
    @Query("""
            SELECT DISTINCT indv_id, ssn FROM stg_trs_h_dc_indv WHERE ssa_validation_sw = 'Y' AND ssn > 0
            """)
    List<ValidSsn> fetchValidSsns();
}
