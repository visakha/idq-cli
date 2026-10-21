package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.eci.etldb.models.EciTargets;

/// `C_S_ECI_PTY_RLE_PHN` - family phones, loaded by `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`.
public interface EciPhoneRepository extends TargetTableRepository<EciTargets.Phone, String>,
        InsertRepository<EciTargets.Phone> {

    String TABLE = "C_S_ECI_PTY_RLE_PHN";
}
