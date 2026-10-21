/// FSS source system, IDQ workflow `wf_FSS_Stage_Load`, mappings 019 to 024.
///
/// Every mapping reads the source views through [FssQueries], transforms in its own class and is loaded by the
/// generic `core.target.TargetWriter`. To be migrated to the ECI `etldb` / `etlmap` layout.
package com.idq.cli.source.fss;
