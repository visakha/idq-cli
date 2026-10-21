package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_MNG_ATTR` - party switches and flags.
public interface TrsManagedAttributeRepository extends TargetTableRepository<TrsTargets.ManagedAttribute, String>,
        InsertRepository<TrsTargets.ManagedAttribute> {

    String TABLE = "C_S_TRS_PTY_MNG_ATTR";
}
