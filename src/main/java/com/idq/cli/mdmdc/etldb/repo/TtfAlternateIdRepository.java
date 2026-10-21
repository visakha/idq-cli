package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.TtfTargets;

/// `C_S_TTF_PTY_RLE_ALT_ID` - alternate identifiers.
public interface TtfAlternateIdRepository extends TargetTableRepository<TtfTargets.AlternateId, String>,
        InsertRepository<TtfTargets.AlternateId> {

    String TABLE = "C_S_TTF_PTY_RLE_ALT_ID";
}
