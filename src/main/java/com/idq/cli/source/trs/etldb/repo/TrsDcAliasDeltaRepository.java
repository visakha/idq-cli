package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberAlias;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_DC_ALIAS` - alias names of the day (together with the MCI aliases).
public interface TrsDcAliasDeltaRepository extends Repository<TrsSources.DcAliasDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_Nm`: the `IdqMapInitQuery`.
    @Query("""
            SELECT DISTINCT a.indv_id, a.pkey_pty, RTRIM(LTRIM(a.first_name)) AS first_name,
                   RTRIM(LTRIM(a.mid_name)) AS mid_name, RTRIM(LTRIM(a.last_name)) AS last_name,
                   RTRIM(a.sufx_name) AS sufx_name, RTRIM(a.prefix_name) AS prefix_name, a.create_dt, a.sequence_num
            FROM (
                SELECT indv_id, TO_CHAR(indv_id) AS pkey_pty, first_name, mid_name, last_name, sufx_name,
                       prefix_name, create_dt, sequence_num
                FROM stg_trs_d_cv_dc_mci_alias
                UNION ALL
                SELECT indv_id, TO_CHAR(indv_id) || '|DC_INDV', first_name, mid_name, last_name, sufx_name,
                       prefix_name, create_dt, seq_num
                FROM stg_trs_d_dc_alias
            ) a
            JOIN stg_trs_valid_members vm ON a.pkey_pty = vm.pty_pk
            """)
    List<MemberAlias> fetchMemberAliases();
}
