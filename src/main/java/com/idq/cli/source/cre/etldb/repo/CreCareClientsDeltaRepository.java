package com.idq.cli.source.cre.etldb.repo;

import com.idq.cli.source.cre.etldb.models.CreQueryRows.CareClient;
import com.idq.cli.source.cre.etldb.models.CreSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_CRE_D_CARE_CLIENTS` - the daily CARE client delta, read by the only CRE mapping.
public interface CreCareClientsDeltaRepository extends Repository<CreSources.CareClientsDelta, String> {

    /// `m_Tgt_C_S_CRE_CARE_Clients`: the `IdqMapInitQuery` (`Read_Stg_CRE_D_CARE_Clients`). New and changed
    /// clients, the deleted or moved cases from the snapshot (`STG_CRE_SN_CARE_CLIENTS`) and the targets of the moves.
    /// The parallel hint and the commented test filters of the IDQ query are left out.
    @Query("""
            SELECT DISTINCT
                   clients.care_id, clients.care_lastup_dt, clients.firstnm, clients.lastnm, clients.last_suf,
                   clients.birth_dt, clients.sex, clients.street, clients.city, clients.cnty, clients.state,
                   clients.zip, clients.zipsuf, clients.phone, clients.recip_no, clients.maint_flag, clients.ssn,
                   clients.insert_date, clients.fedeth, clients.race,
                   NULL AS source_id, NULL AS target_id, NULL AS rec, 'I' AS rec_type
            FROM stg_cre_d_care_clients clients
            WHERE clients.maint_flag IS NULL
            UNION ALL
            SELECT DISTINCT
                   clients.care_id, clients.care_lastup_dt, clients.firstnm, clients.lastnm, clients.last_suf,
                   clients.birth_dt, clients.sex, clients.street, clients.city, clients.cnty, clients.state,
                   clients.zip, clients.zipsuf, clients.phone, clients.recip_no, deltas.maint_flag, clients.ssn,
                   clients.insert_date, clients.fedeth, clients.race,
                   maint.source_id, maint.target_id, maint.rec, DECODE(maint.rec, 'CASEMOV', 'B', 'D')
            FROM stg_cre_d_care_clients deltas
            LEFT JOIN stg_cre_sn_care_clients clients ON deltas.care_id = clients.care_id
            JOIN stg_cre_d_care_case_maint maint
              ON clients.care_id = maint.source_id
             AND deltas.maint_flag = 'D'
             AND maint.rec IN ('CASEMOV', 'CASEDEL')
            UNION ALL
            SELECT DISTINCT
                   clients.care_id, clients.care_lastup_dt, clients.firstnm, clients.lastnm, clients.last_suf,
                   clients.birth_dt, clients.sex, clients.street, clients.city, clients.cnty, clients.state,
                   clients.zip, clients.zipsuf, clients.phone, clients.recip_no, clients.maint_flag, clients.ssn,
                   clients.insert_date, clients.fedeth, clients.race,
                   maint.source_id, maint.target_id, maint.rec, 'A' AS rec_type
            FROM stg_cre_sn_care_clients clients
            JOIN stg_cre_d_care_case_maint maint
              ON clients.care_id = maint.target_id
             AND maint.rec = 'CASEMOV'
            """)
    List<CareClient> fetchCareClients();
}
