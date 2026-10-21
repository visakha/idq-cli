package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.fss.etldb.models.FssTargets;

/// `C_S_FSS_PTY_RLE_EADDR` - e-mail addresses.
public interface FssEmailRepository extends TargetTableRepository<FssTargets.Email, String>,
        InsertRepository<FssTargets.Email> {

    String TABLE = "C_S_FSS_PTY_RLE_EADDR";
}
