package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.eci.etldb.models.EciTargets;

/// `C_S_ECI_PTY_RLE` - member role of each party, loaded by `m_Tgt_C_S_ECI_Pty`.
public interface EciPartyRoleRepository extends TargetTableRepository<EciTargets.PartyRole, String>,
        InsertRepository<EciTargets.PartyRole> {

    String TABLE = "C_S_ECI_PTY_RLE";
}
