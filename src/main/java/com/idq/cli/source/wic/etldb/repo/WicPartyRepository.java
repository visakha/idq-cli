package com.idq.cli.source.wic.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.wic.etldb.models.WicTargets;

/// `C_S_WIC_PTY` - demographics.
public interface WicPartyRepository extends TargetTableRepository<WicTargets.Party, String>,
        InsertRepository<WicTargets.Party> {

    String TABLE = "C_S_WIC_PTY";
}
