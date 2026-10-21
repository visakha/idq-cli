package com.idq.cli.source.wic.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.wic.etldb.models.WicTargets;
import org.springframework.data.repository.Repository;

/// `STG_WIC_PTY_INACTIVE_LOG` - every deactivation and reactivation, only ever appended.
public interface WicInactiveLogRepository extends Repository<WicTargets.InactiveLog, String>,
        InsertRepository<WicTargets.InactiveLog> {

    String TABLE = "STG_WIC_PTY_INACTIVE_LOG";
}
