package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.CreTargets;

/// `C_S_CRE_PTY` - demographics.
public interface CrePartyRepository extends TargetTableRepository<CreTargets.Party, String>,
        InsertRepository<CreTargets.Party> {

    String TABLE = "C_S_CRE_PTY";
}
