package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.ManagedCarePlan;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.PrimaryCareProvider;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_IN_MANAGED_CARE` - managed care enrolments of the day.
public interface TrsInManagedCareDeltaRepository extends Repository<TrsSources.InManagedCareDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_Rle_Pln`: the `IdqMapInitQuery`.
    @Query("""
            SELECT DISTINCT m.indv_id, m.begin_dt, m.mc_plan, m.history_seq, m.end_dt, m.create_dt
            FROM stg_trs_d_in_managed_care m
            JOIN stg_trs_valid_members vm ON m.indv_id = vm.indv_id AND vm.src_tbl = 'MCI'
            WHERE m.mc_plan IS NOT NULL AND (m.begin_dt < m.end_dt OR m.end_dt IS NULL)
            ORDER BY m.indv_id, m.mc_plan, m.begin_dt, m.end_dt
            """)
    List<ManagedCarePlan> fetchManagedCarePlans();

    /// `m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`: the `IdqMapInitQuery`.
    @Query("""
            WITH min_pk AS (
                SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
            )
            SELECT mc.indv_id, mc.history_seq, mc.mc_prog_code, mc.begin_dt, mc.create_dt, mc.provider_num,
                   mc.end_dt, vm.pty_pk
            FROM stg_trs_d_in_managed_care mc
            JOIN min_pk vm ON mc.indv_id = vm.indv_id
            WHERE mc.provider_num IS NOT NULL
            ORDER BY mc.indv_id, mc.end_dt
            """)
    List<PrimaryCareProvider> fetchPrimaryCareProviders();
}
