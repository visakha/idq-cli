package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.FssTargets;

/// `C_S_FSS_PTY_RLE_PHN` - phone numbers.
public interface FssPhoneRepository extends TargetTableRepository<FssTargets.Phone, String>,
        InsertRepository<FssTargets.Phone> {

    String TABLE = "C_S_FSS_PTY_RLE_PHN";
}
