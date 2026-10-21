package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyDemographics;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyIdentifier;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyName;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_ECI_D_CHILD` - the `IdqMapInitQuery`s driven by the child delta (children, plus the family members and
/// Medicaid numbers joined to them).
public interface EciChildDeltaRepository extends Repository<EciSources.ChildDelta, Long> {

    /// `m_Tgt_C_S_ECI_Pty_Validation`: names of every child and family member.
    @Query("""
            SELECT 'ECI_CHILD' AS source_table, id_child AS id, first_name, last_name, middle_initial, dob,
                   date_created, date_modified, modified_by, created_by, load_date
            FROM stg_eci_d_child
            UNION ALL
            SELECT 'ECI_FAMILY', id_family, first_name, last_name, middle_initial, dob, date_created, date_modified,
                   modified_by, created_by, load_date
            FROM stg_eci_d_family
            """)
    List<PartyName> fetchPartyNames();

    /// `m_Tgt_C_S_ECI_Pty`: demographics of every child and family member.
    @Query("""
            SELECT 'ECI_CHILD' AS source_table, child.id_child AS id, child.child_ssn, child.first_name,
                   child.last_name, child.middle_initial, child.dob, child.gestation_age, child.gender,
                   child.birth_wt_lb, child.birth_wt_oz, child.interpret_ind, child.language_cd, child.race_cd,
                   child.date_created, COALESCE(child.date_modified, child.date_created) AS date_modified,
                   child.modified_by, child.created_by, child.ethnicity, child.race_white, child.race_aa,
                   child.race_asian, child.race_pi, child.race_an, child.load_date
            FROM stg_eci_d_child child
            UNION ALL
            SELECT 'ECI_FAMILY', fam.id_family, NULL, fam.first_name, fam.last_name, fam.middle_initial, fam.dob,
                   NULL, fam.gender, NULL, NULL, NULL, NULL, NULL, fam.date_created,
                   COALESCE(fam.date_modified, fam.date_created), fam.modified_by, fam.created_by, NULL, NULL, NULL,
                   NULL, NULL, NULL, fam.load_date
            FROM stg_eci_d_family fam
            """)
    List<PartyDemographics> fetchPartyDemographics();

    /// `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`: child id, child SSN, Medicaid number and family id, key already formulated.
    @Query("""
            SELECT id_child AS id, LPAD(id_child, 10, '0') || '|Member' AS pty_rel_fk,
                   LPAD(id_child, 10, '0') AS src_key_sfx, '018' alt_id_tp, LPAD(id_child, 10, '0') alt_id_val,
                   date_created, date_modified,
                   LPAD(id_child, 10, '0') || '|Member' || '|018' || '|' || LPAD(id_child, 10, '0') AS pkey_src_object
            FROM stg_eci_d_child
            UNION ALL
            SELECT id_child, LPAD(id_child, 10, '0') || '|Member', LPAD(id_child, 10, '0'), '004', child_ssn,
                   date_created, date_modified,
                   LPAD(id_child, 10, '0') || '|Member' || '|004' || '|' || LPAD(id_child, 10, '0')
            FROM stg_eci_d_child
            WHERE child_ssn IS NOT NULL
            UNION ALL
            SELECT id_child, LPAD(id_child, 10, '0') || '|Member', LPAD(id_medicaid, 9, '0'), '002', medicaid_nbr,
                   m.date_created, m.date_modified,
                   LPAD(id_child, 10, '0') || '|Member' || '|002' || '|' || LPAD(id_medicaid, 10, '0')
            FROM stg_eci_d_medicaid m
            JOIN stg_eci_sn_case c ON m.id_case = c.id_case
            UNION ALL
            SELECT id_family, LPAD(id_family, 10, '0') || 'F|Member', LPAD(id_family, 10, '0'), '019',
                   LPAD(id_family, 10, '0'), date_created, date_modified,
                   LPAD(id_family, 10, '0') || 'F|Member' || '|019' || '|' || LPAD(id_family, 10, '0')
            FROM stg_eci_d_family
            """)
    List<PartyIdentifier> fetchPartyIdentifiers();
}
