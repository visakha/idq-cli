package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.trs.etldb.models.TrsTargets;

/// `C_S_TRS_PTY` - demographics.
public interface TrsPartyRepository extends TargetTableRepository<TrsTargets.Party, String>,
        InsertRepository<TrsTargets.Party> {

    String TABLE = "C_S_TRS_PTY";
}
