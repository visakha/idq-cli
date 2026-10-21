package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.core.repo.TargetTableRepository;
import com.idq.cli.source.eci.etldb.models.EciTargets;

/// `C_S_ECI_PTY_RLE_REL` - child / family member relationships, loaded by `m_Tgt_C_S_ECI_Pty_Rle_Rel`.
public interface EciRelationshipRepository extends TargetTableRepository<EciTargets.Relationship, String>,
        InsertRepository<EciTargets.Relationship> {

    String TABLE = "C_S_ECI_PTY_RLE_REL";
}
