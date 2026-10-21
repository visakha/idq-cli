package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.CreTargets;

/// `C_S_CRE_PTY_RLE_ALT_ID` - alternate identifiers.
public interface CreAlternateIdRepository extends TargetTableRepository<CreTargets.AlternateId, String>,
        InsertRepository<CreTargets.AlternateId> {

    String TABLE = "C_S_CRE_PTY_RLE_ALT_ID";
}
