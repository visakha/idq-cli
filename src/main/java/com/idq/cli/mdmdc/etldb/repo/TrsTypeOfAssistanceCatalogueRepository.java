package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_LU_TOA` - the type-of-assistance catalogue.
public interface TrsTypeOfAssistanceCatalogueRepository
        extends TargetTableRepository<TrsTargets.TypeOfAssistanceCatalogue, String>,
        InsertRepository<TrsTargets.TypeOfAssistanceCatalogue> {

    String TABLE = "C_S_LU_TOA";
}
