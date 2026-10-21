package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientRelation;
import com.idq.cli.source.fss.etldb.models.FssSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `V_FSS_ETL_SRC_RELATIONS` - relations between clients of a registration.
public interface FssEtlSrcRelationsViewRepository extends Repository<FssSources.EtlSrcRelations, Long> {

    /// `m_Tgt_C_S_FSS_Pty_Rle_Rel`: the `IdqMapInitQuery`.
    @Query("""
            SELECT relation_direction, reln_id_client, reln_cd_gender, id_client, pty_src_key, reln_pty_src_key,
                   reln_dt_last_update, reln_dt_created, cd_reltshp_to_tc, cd_gender, id_registration
            FROM v_fss_etl_src_relations
            """)
    List<ClientRelation> fetchClientRelations();
}
