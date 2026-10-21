package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_ADDR` - postal addresses.
public interface TrsAddressRepository extends TargetTableRepository<TrsTargets.Address, String>,
        InsertRepository<TrsTargets.Address> {

    String TABLE = "C_S_TRS_PTY_RLE_ADDR";
}
