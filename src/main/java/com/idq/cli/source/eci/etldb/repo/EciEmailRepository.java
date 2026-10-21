package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.eci.etldb.models.EciTargets;

/// `C_S_ECI_PTY_RLE_EADDR` - family e-mail addresses, loaded by `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`.
public interface EciEmailRepository extends TargetTableRepository<EciTargets.Email, String>,
        InsertRepository<EciTargets.Email> {

    String TABLE = "C_S_ECI_PTY_RLE_EADDR";
}
