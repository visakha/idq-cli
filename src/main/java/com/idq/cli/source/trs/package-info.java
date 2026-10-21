/// TRS (TIERS eligibility system), IDQ workflow `wf_TRS_Stage_Load_1_Ongoing`, mappings 001 to 012.
///
/// Every mapping reads its `IdqMapInitQuery` through [TrsQueries], transforms in its own class and is loaded by the
/// generic `core.target.TargetWriter`. To be migrated to the ECI `etldb` / `etlmap` layout.
package com.idq.cli.source.trs;
