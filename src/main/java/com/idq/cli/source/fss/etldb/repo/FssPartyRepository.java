package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.fss.etldb.models.FssTargets;

/// `C_S_FSS_PTY` - demographics.
public interface FssPartyRepository extends TargetTableRepository<FssTargets.Party, String>,
        InsertRepository<FssTargets.Party> {

    String TABLE = "C_S_FSS_PTY";
}
