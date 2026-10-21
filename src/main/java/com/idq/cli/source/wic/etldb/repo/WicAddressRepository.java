package com.idq.cli.source.wic.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.wic.etldb.models.WicTargets;

/// `C_S_WIC_PTY_RLE_ADDR` - postal addresses.
public interface WicAddressRepository extends TargetTableRepository<WicTargets.Address, String>,
        InsertRepository<WicTargets.Address> {

    String TABLE = "C_S_WIC_PTY_RLE_ADDR";
}
