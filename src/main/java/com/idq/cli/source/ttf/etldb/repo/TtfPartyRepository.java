package com.idq.cli.source.ttf.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.ttf.etldb.models.TtfTargets;

/// `C_S_TTF_PTY` - demographics.
public interface TtfPartyRepository extends TargetTableRepository<TtfTargets.Party, String>,
        InsertRepository<TtfTargets.Party> {

    String TABLE = "C_S_TTF_PTY";
}
