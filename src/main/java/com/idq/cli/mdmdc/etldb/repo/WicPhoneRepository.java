package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.WicTargets;

/// `C_S_WIC_PTY_RLE_PHN` - phone numbers.
public interface WicPhoneRepository extends TargetTableRepository<WicTargets.Phone, String>,
        InsertRepository<WicTargets.Phone> {

    String TABLE = "C_S_WIC_PTY_RLE_PHN";
}
