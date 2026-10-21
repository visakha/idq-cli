package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_REL` - relationships between two members.
public interface TrsRelationshipRepository extends TargetTableRepository<TrsTargets.Relationship, String>,
        InsertRepository<TrsTargets.Relationship> {

    String TABLE = "C_S_TRS_PTY_RLE_REL";
}
