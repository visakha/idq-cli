package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.trs.etldb.models.TrsTargets;

/// `C_S_TRS_PTY_RLE_EADDR` - e-mail addresses.
public interface TrsEmailRepository extends TargetTableRepository<TrsTargets.Email, String>,
        InsertRepository<TrsTargets.Email> {

    String TABLE = "C_S_TRS_PTY_RLE_EADDR";
}
