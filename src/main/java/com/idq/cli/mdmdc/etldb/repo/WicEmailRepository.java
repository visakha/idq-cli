package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.WicTargets;

/// `C_S_WIC_PTY_RLE_EADDR` - e-mail addresses.
public interface WicEmailRepository extends TargetTableRepository<WicTargets.Email, String>,
        InsertRepository<WicTargets.Email> {

    String TABLE = "C_S_WIC_PTY_RLE_EADDR";
}
