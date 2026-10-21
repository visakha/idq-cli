package com.idq.cli.source.ttf.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.ttf.etldb.models.TtfTargets;
import org.springframework.data.repository.Repository;

/// `STG_TTF_PTY_INACTIVE_LOG` - every deactivation and reactivation, only ever appended.
public interface TtfInactiveLogRepository extends Repository<TtfTargets.InactiveLog, String>,
        InsertRepository<TtfTargets.InactiveLog> {

    String TABLE = "STG_TTF_PTY_INACTIVE_LOG";
}
