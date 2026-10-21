package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.trs.etldb.models.TrsTargets;

/// `STG_TRS_D_UNQ_ADDR` - distinct validated addresses of the day.
public interface TrsUniqueAddressDeltaRepository extends TargetTableRepository<TrsTargets.UniqueAddressDelta, String>,
        InsertRepository<TrsTargets.UniqueAddressDelta> {

    String TABLE = "STG_TRS_D_UNQ_ADDR";
}
