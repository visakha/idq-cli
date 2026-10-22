package com.idq.cli.source.cre.etldb.repo;

import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.source.cre.etldb.models.CreQueryRows.PartyXref;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `C_B_PTY_XREF` - MDM base table, restricted to the CRE cross-references.
public interface CrePartyXrefRepository extends Repository<MdmBaseTables.PartyXref, Long> {

    /// `LKP_XREF_SRC` / `LKP_XREF_TGT`: the MDM record and its original record of each CARE id. `ROWID_SYSTEM` is
    /// blank-padded (`CHAR(14)`; IDQ filters on `'CRE           '`), hence the trim.
    @Query("""
            SELECT pkey_src_object, rowid_object, orig_rowid_object FROM c_b_pty_xref
            WHERE TRIM(rowid_system) = 'CRE'
            """)
    List<PartyXref> fetchCrossReferences();
}
