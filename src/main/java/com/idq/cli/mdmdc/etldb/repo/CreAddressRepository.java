package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.CreTargets;

/// `C_S_CRE_PTY_RLE_ADDR` - postal addresses.
public interface CreAddressRepository extends TargetTableRepository<CreTargets.Address, String>,
        InsertRepository<CreTargets.Address> {

    String TABLE = "C_S_CRE_PTY_RLE_ADDR";
}
