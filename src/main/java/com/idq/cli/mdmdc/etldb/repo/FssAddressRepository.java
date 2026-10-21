package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.FssTargets;

/// `C_S_FSS_PTY_RLE_ADDR` - postal addresses.
public interface FssAddressRepository extends TargetTableRepository<FssTargets.Address, String>,
        InsertRepository<FssTargets.Address> {

    String TABLE = "C_S_FSS_PTY_RLE_ADDR";
}
