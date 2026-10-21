package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.EciTargets;

/// `C_S_ECI_PTY` - demographics, loaded by `m_Tgt_C_S_ECI_Pty`.
public interface EciPartyRepository extends TargetTableRepository<EciTargets.Party, String>,
        InsertRepository<EciTargets.Party> {

    String TABLE = "C_S_ECI_PTY";
}
