package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.trs.etldb.models.TrsSources;

/// `STG_TRS_D_UNQ_ADDR` - distinct validated addresses of the day.
public interface TrsUniqueAddressDeltaRepository extends TargetTableRepository<TrsSources.UniqueAddressDelta, String>,
        InsertRepository<TrsSources.UniqueAddressDelta> {

    String TABLE = "STG_TRS_D_UNQ_ADDR";
}
