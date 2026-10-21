package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_PLN` - managed care plan enrolment.
public interface TrsPlanRepository extends TargetTableRepository<TrsTargets.Plan, String>,
        InsertRepository<TrsTargets.Plan> {

    String TABLE = "C_S_TRS_PTY_RLE_PLN";
}
