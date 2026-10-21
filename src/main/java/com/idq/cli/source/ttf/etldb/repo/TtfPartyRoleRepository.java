package com.idq.cli.source.ttf.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.ttf.etldb.models.TtfTargets;

/// `C_S_TTF_PTY_RLE` - member role of each party.
public interface TtfPartyRoleRepository extends TargetTableRepository<TtfTargets.PartyRole, String>,
        InsertRepository<TtfTargets.PartyRole> {

    String TABLE = "C_S_TTF_PTY_RLE";
}
