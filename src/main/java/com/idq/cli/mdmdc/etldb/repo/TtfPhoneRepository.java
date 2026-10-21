package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TtfTargets;

/// `C_S_TTF_PTY_RLE_PHN` - phone numbers.
public interface TtfPhoneRepository extends TargetTableRepository<TtfTargets.Phone, String>,
        InsertRepository<TtfTargets.Phone> {

    String TABLE = "C_S_TTF_PTY_RLE_PHN";
}
