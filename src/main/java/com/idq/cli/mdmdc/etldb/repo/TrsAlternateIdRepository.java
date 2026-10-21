package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_ALT_ID` - alternate identifiers.
public interface TrsAlternateIdRepository extends TargetTableRepository<TrsTargets.AlternateId, String>,
        InsertRepository<TrsTargets.AlternateId> {

    String TABLE = "C_S_TRS_PTY_RLE_ALT_ID";
}
