package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.eci.etldb.models.EciSources;
import org.springframework.data.repository.Repository;

/// `STG_ECI_PTY_INACTIVE_LOG` - every deactivation and reactivation, only ever appended.
public interface EciInactiveLogRepository extends Repository<EciSources.InactiveLog, String>,
        InsertRepository<EciSources.InactiveLog> {

    String TABLE = "STG_ECI_PTY_INACTIVE_LOG";
}
