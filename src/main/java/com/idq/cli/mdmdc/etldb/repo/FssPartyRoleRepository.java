package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.FssTargets;

/// `C_S_FSS_PTY_RLE` - member role of each party.
public interface FssPartyRoleRepository extends TargetTableRepository<FssTargets.PartyRole, String>,
        InsertRepository<FssTargets.PartyRole> {

    String TABLE = "C_S_FSS_PTY_RLE";
}
