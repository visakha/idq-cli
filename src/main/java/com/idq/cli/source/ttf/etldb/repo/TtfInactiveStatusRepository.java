package com.idq.cli.source.ttf.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.ttf.etldb.models.TtfTargets;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Modifying;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/// `STG_TTF_PTY_INACTIVE_STS` - the parties currently deactivated. Written by the TTF validation mapping, read by every
/// later mapping of the workflow to drop deactivated parties.
public interface TtfInactiveStatusRepository extends Repository<TtfTargets.InactiveStatus, String>,
        InsertRepository<TtfTargets.InactiveStatus> {

    String TABLE = "STG_TTF_PTY_INACTIVE_STS";

    /// `Lookup_STG_TTF_PTY_INACTIVE_STS`: deactivation status per party source key.
    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_ttf_pty_inactive_sts
            WHERE rowid_system = 'TTF' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

    /// Reactivation: the party's status row is removed (IDQ update strategy `DD_DELETE`).
    @Modifying
    @Query("DELETE FROM STG_TTF_PTY_INACTIVE_STS WHERE SRC_KEY = :srcKey AND ROWID_SYSTEM = :rowidSystem")
    int deleteBySrcKeyAndRowidSystem(@Param("srcKey") String srcKey, @Param("rowidSystem") String rowidSystem);
}
