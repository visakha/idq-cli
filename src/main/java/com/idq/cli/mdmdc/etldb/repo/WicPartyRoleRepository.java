package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.WicTargets;

/// `C_S_WIC_PTY_RLE` - member role of each party.
public interface WicPartyRoleRepository extends TargetTableRepository<WicTargets.PartyRole, String>,
        InsertRepository<WicTargets.PartyRole> {

    String TABLE = "C_S_WIC_PTY_RLE";
}
