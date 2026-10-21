package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_REL_PROV` - member to primary care provider.
public interface TrsProviderRelationshipRepository
        extends TargetTableRepository<TrsTargets.ProviderRelationship, String>,
        InsertRepository<TrsTargets.ProviderRelationship> {

    String TABLE = "C_S_TRS_PTY_RLE_REL_PROV";
}
