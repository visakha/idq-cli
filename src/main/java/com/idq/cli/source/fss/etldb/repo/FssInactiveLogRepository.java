package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.fss.etldb.models.FssSources;
import org.springframework.data.repository.Repository;

/// `STG_FSS_PTY_INACTIVE_LOG` - every deactivation and reactivation, only ever appended.
public interface FssInactiveLogRepository extends Repository<FssSources.InactiveLog, String>,
        InsertRepository<FssSources.InactiveLog> {

    String TABLE = "STG_FSS_PTY_INACTIVE_LOG";
}
