package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE` - member role of each party.
public interface TrsPartyRoleRepository extends TargetTableRepository<TrsTargets.PartyRole, String>,
        InsertRepository<TrsTargets.PartyRole> {

    String TABLE = "C_S_TRS_PTY_RLE";
}
