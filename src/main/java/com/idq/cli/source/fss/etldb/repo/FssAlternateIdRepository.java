package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.fss.etldb.models.FssTargets;

/// `C_S_FSS_PTY_RLE_ALT_ID` - alternate identifiers.
public interface FssAlternateIdRepository extends TargetTableRepository<FssTargets.AlternateId, String>,
        InsertRepository<FssTargets.AlternateId> {

    String TABLE = "C_S_FSS_PTY_RLE_ALT_ID";
}
