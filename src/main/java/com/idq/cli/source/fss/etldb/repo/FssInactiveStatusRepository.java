package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.fss.etldb.models.FssSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_FSS_PTY_INACTIVE_STS` - the parties currently deactivated. Written by the FSS validation mapping, read by every
/// later mapping of the workflow to drop deactivated parties.
public interface FssInactiveStatusRepository extends Repository<FssSources.InactiveStatus, String>,
        InsertRepository<FssSources.InactiveStatus> {

    String TABLE = "STG_FSS_PTY_INACTIVE_STS";

    /// `Lookup_STG_FSS_PTY_INACTIVE_STS`: deactivation status per party source key.
    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_fss_pty_inactive_sts
            WHERE rowid_system = 'FSS' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

}
