package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.trs.etldb.models.TrsTargets;
import org.springframework.data.jdbc.repository.query.Modifying;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.query.Param;

/// `C_S_TRS_PTY_MNG_ATTR` - party switches and flags.
public interface TrsManagedAttributeRepository extends TargetTableRepository<TrsTargets.ManagedAttribute, String>,
        InsertRepository<TrsTargets.ManagedAttribute> {

    String TABLE = "C_S_TRS_PTY_MNG_ATTR";

    /// IDQ pre-SQL of the authorized-representative mapping: only its own attribute type is replaced.
    @Modifying
    @Query("DELETE FROM C_S_TRS_PTY_MNG_ATTR WHERE MNG_ATTR_TP = :mngAttrTp")
    int deleteByMngAttrTp(@Param("mngAttrTp") String mngAttrTp);
}
