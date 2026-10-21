package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.FssTargets;

/// `C_S_FSS_PTY_RLE_REL` - relationships between two members.
public interface FssRelationshipRepository extends TargetTableRepository<FssTargets.Relationship, String>,
        InsertRepository<FssTargets.Relationship> {

    String TABLE = "C_S_FSS_PTY_RLE_REL";
}
