package com.idq.cli.source.ttf.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyNumber;
import com.idq.cli.core.reference.MdmBaseTables;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `C_B_PTY_XREF` - MDM base table, restricted to the TTF cross-references.
public interface TtfPartyXrefRepository extends Repository<MdmBaseTables.PartyXref, Long> {

    /// `Lookup_C_B_PTY_XREF`: hub state of each TTF party in MDM.
    @Query("""
            SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
            WHERE TRIM(rowid_system) = 'TTF'
            """)
    List<KeyNumber> fetchHubStates();
}
