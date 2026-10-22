package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceType;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_LU_TOA` - the TIERS type-of-assistance catalogue.
public interface TrsLuToaDeltaRepository extends Repository<TrsSources.LuToaDelta, String> {

    /// `m_Tgt_C_S_TRS_Stg_TOA`: the `IdqMapInitQuery` (every row; the lookups are done in Java).
    @Query("""
            SELECT program_code, toa_code, toa_desc, eff_begin_dt, eff_end_dt, create_dt, update_user_id,
                   update_dt, unique_trans_id
            FROM stg_trs_d_lu_toa
            """)
    List<AssistanceType> fetchAssistanceTypes();
}
