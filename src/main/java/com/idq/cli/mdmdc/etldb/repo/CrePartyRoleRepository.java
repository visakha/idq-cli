package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.CreTargets;

/// `C_S_CRE_PTY_RLE` - member role of each party.
public interface CrePartyRoleRepository extends TargetTableRepository<CreTargets.PartyRole, String>,
        InsertRepository<CreTargets.PartyRole> {

    String TABLE = "C_S_CRE_PTY_RLE";
}
