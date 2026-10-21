package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.eci.etldb.models.EciTargets;

/// `C_S_ECI_PTY_RLE_ADDR` - family addresses, loaded by `m_Tgt_C_S_ECI_Pty_Addr`.
public interface EciAddressRepository extends TargetTableRepository<EciTargets.Address, String>,
        InsertRepository<EciTargets.Address> {

    String TABLE = "C_S_ECI_PTY_RLE_ADDR";
}
