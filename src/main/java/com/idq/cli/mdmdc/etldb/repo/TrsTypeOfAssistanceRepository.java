package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_TOA` - type of assistance segments.
public interface TrsTypeOfAssistanceRepository extends TargetTableRepository<TrsTargets.TypeOfAssistance, String>,
        InsertRepository<TrsTargets.TypeOfAssistance> {

    String TABLE = "C_S_TRS_PTY_RLE_TOA";
}
