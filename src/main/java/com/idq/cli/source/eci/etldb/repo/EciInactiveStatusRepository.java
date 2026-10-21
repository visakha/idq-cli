package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_ECI_PTY_INACTIVE_STS` - the parties currently deactivated. Written by `m_Tgt_C_S_ECI_Pty_Validation`, read
/// by every later ECI mapping to drop deactivated parties.
public interface EciInactiveStatusRepository extends Repository<EciSources.InactiveStatus, String>,
        InsertRepository<EciSources.InactiveStatus> {

    String TABLE = "STG_ECI_PTY_INACTIVE_STS";

    /// `Lookup_STG_ECI_PTY_INACTIVE_STS`: deactivation status per party source key.
    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_eci_pty_inactive_sts
            WHERE rowid_system = 'ECI' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

}
