package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.CreTargets;

/// `C_S_CRE_PTY_RLE_PHN` - phone numbers.
public interface CrePhoneRepository extends TargetTableRepository<CreTargets.Phone, String>,
        InsertRepository<CreTargets.Phone> {

    String TABLE = "C_S_CRE_PTY_RLE_PHN";
}
