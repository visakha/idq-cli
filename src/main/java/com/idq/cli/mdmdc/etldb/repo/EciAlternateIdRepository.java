package com.idq.cli.mdmdc.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.mdmdc.etldb.models.EciTargets;

/// `C_S_ECI_PTY_RLE_ALT_ID` - child / family ids, SSN and Medicaid number, loaded by `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`.
public interface EciAlternateIdRepository extends TargetTableRepository<EciTargets.AlternateId, String>,
        InsertRepository<EciTargets.AlternateId> {

    String TABLE = "C_S_ECI_PTY_RLE_ALT_ID";
}
