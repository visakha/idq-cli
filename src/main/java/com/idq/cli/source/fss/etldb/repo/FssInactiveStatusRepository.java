package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.fss.etldb.models.FssTargets;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Modifying;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/// `STG_FSS_PTY_INACTIVE_STS` - the parties currently deactivated. Written by the FSS validation mapping, read by every
/// later mapping of the workflow to drop deactivated parties.
public interface FssInactiveStatusRepository extends Repository<FssTargets.InactiveStatus, String>,
        InsertRepository<FssTargets.InactiveStatus> {

    String TABLE = "STG_FSS_PTY_INACTIVE_STS";

    /// `Lookup_STG_FSS_PTY_INACTIVE_STS`: deactivation status per party source key.
    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_fss_pty_inactive_sts
            WHERE rowid_system = 'FSS' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

    /// Reactivation: the party's status row is removed (IDQ update strategy `DD_DELETE`).
    @Modifying
    @Query("DELETE FROM STG_FSS_PTY_INACTIVE_STS WHERE SRC_KEY = :srcKey AND ROWID_SYSTEM = :rowidSystem")
    int deleteBySrcKeyAndRowidSystem(@Param("srcKey") String srcKey, @Param("rowidSystem") String rowidSystem);
}
