package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyRelation;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_ECI_D_FAMILY` - family members and the child each one belongs to.
public interface EciFamilyDeltaRepository extends Repository<EciSources.FamilyDelta, Long> {

    /// `m_Tgt_C_S_ECI_Pty_Rle_Rel`: every family member / child pair, once per direction.
    @Query("""
            SELECT d.relation_direction, f.id_family, f.gender AS family_gender, f.id_child,
                   TO_CHAR(f.family_cd) AS family_cd, COALESCE(f.date_modified, f.date_created) AS date_modified,
                   f.date_created
            FROM stg_eci_d_family f
            JOIN (SELECT 'From Child' relation_direction FROM dual
                  UNION ALL
                  SELECT 'To Child' FROM dual) d ON 1 = 1
            """)
    List<FamilyRelation> fetchFamilyRelations();
}
