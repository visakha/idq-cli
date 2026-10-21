package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_PHN` - phone numbers.
public interface TrsPhoneRepository extends TargetTableRepository<TrsTargets.Phone, String>,
        InsertRepository<TrsTargets.Phone> {

    String TABLE = "C_S_TRS_PTY_RLE_PHN";
}
