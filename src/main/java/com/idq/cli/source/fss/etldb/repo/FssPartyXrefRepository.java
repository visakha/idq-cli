package com.idq.cli.source.fss.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyNumber;
import com.idq.cli.core.reference.MdmBaseTables;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `C_B_PTY_XREF` - MDM base table, restricted to the FSS cross-references.
public interface FssPartyXrefRepository extends Repository<MdmBaseTables.PartyXref, Long> {

    /// `Lookup_C_B_PTY_XREF`: hub state of each FSS party in MDM.
    @Query("""
            SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
            WHERE rowid_system = 'FSS'
            """)
    List<KeyNumber> fetchHubStates();
}
