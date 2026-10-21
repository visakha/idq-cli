package com.idq.cli.source.cre.etldb.repo;

import com.idq.cli.core.reference.MdmBaseTables;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `C_B_PTY_HMRG` - MDM merge history of the party base object.
public interface CrePartyHmrgRepository extends Repository<MdmBaseTables.PartyHmrg, String> {

    /// `LKP_HMRG_SRC1` / `_SRC2` / `_TGT1` / `_TGT2`: every merge (source and target record).
    @Query("SELECT src_rowid_object, tgt_rowid_object FROM c_b_pty_hmrg")
    List<MdmBaseTables.PartyHmrg> fetchMergeHistory();
}
