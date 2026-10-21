package com.idq.cli.source.wic.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.wic.etldb.models.WicSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_WIC_PTY_INACTIVE_STS` - the parties currently deactivated. Written by the WIC validation mapping, read by every
/// later mapping of the workflow to drop deactivated parties.
public interface WicInactiveStatusRepository extends Repository<WicSources.InactiveStatus, String>,
        InsertRepository<WicSources.InactiveStatus> {

    String TABLE = "STG_WIC_PTY_INACTIVE_STS";

    /// `Lookup_STG_WIC_PTY_INACTIVE_STS`: deactivation status per party source key.
    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_wic_pty_inactive_sts
            WHERE rowid_system = 'WIC' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

}
