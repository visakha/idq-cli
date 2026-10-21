package com.idq.cli.source.wic.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.wic.etldb.models.WicTargets;

/// `C_S_WIC_PTY_RLE_ALT_ID` - alternate identifiers.
public interface WicAlternateIdRepository extends TargetTableRepository<WicTargets.AlternateId, String>,
        InsertRepository<WicTargets.AlternateId> {

    String TABLE = "C_S_WIC_PTY_RLE_ALT_ID";
}
