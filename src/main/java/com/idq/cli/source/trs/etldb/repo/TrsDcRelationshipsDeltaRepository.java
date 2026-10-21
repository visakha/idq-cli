package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberRelationship;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_DC_RELATIONSHIPS` - relationships between individuals of the day.
public interface TrsDcRelationshipsDeltaRepository extends Repository<TrsSources.DcRelationshipsDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`: the `IdqMapInitQuery`.
    @Query("""
            WITH min_pk AS (
                SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
            )
            SELECT rel.indv_id, rel.ref_indv_id, rel.eff_begin_dt, rel.eff_end_dt, rel.hist_nav_ind,
                   rel.relationship_type_cd, pk1.pty_pk AS pty_pkey, pk2.pty_pk AS ref_pty_pkey,
                   '007' AS pty_alt_id_tp, rel.create_dt, rel.update_dt
            FROM stg_trs_d_dc_relationships rel
            JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
            JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id
            ORDER BY rel.indv_id, rel.eff_end_dt
            """)
    List<MemberRelationship> fetchMemberRelationships();
}
