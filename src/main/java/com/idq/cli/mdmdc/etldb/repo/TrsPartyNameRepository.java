package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_NM` - alternate (alias) names.
public interface TrsPartyNameRepository extends TargetTableRepository<TrsTargets.PartyName, String>,
        InsertRepository<TrsTargets.PartyName> {

    String TABLE = "C_S_TRS_PTY_NM";
}
