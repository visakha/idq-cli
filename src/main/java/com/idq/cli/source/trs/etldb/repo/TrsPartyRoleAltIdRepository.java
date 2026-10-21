package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.ProviderKey;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `C_B_PTY_RLE_ALT_ID` - MDM base table of alternate ids, used for the provider TPI.
public interface TrsPartyRoleAltIdRepository extends Repository<MdmBaseTables.PartyRoleAltId, String> {

    /// MDM provider key per TPI (latest source key).
    @Query("""
            WITH tpi_src_key AS (
                SELECT bo.alt_id_val, xr.pkey_src_object,
                       ROW_NUMBER() OVER (PARTITION BY bo.alt_id_val ORDER BY xr.src_last_upd_dt DESC) src_key_rn
                FROM c_b_pty_rle_alt_id bo
                JOIN c_b_pty_rle_alt_id_xref xr ON bo.rowid_object = xr.rowid_object
                WHERE bo.alt_id_tp = '006' AND xr.rowid_system = 'C21' AND xr.hub_state_ind = 1
            )
            SELECT alt_id_val, pkey_src_object FROM tpi_src_key WHERE src_key_rn = 1
            """)
    List<ProviderKey> fetchProviderKeys();
}
