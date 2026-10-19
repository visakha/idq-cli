package com.idq.cli.source.eci;

import com.idq.cli.core.reference.LookupRows.KeyNumber;
import com.idq.cli.core.reference.LookupRows.KeyValue;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// Named-query interface of the ECI workflow (`wf_ECI_Stage_Load`).
public interface EciQueries extends Repository<EciTargets.InactiveStatus, String> {

    /// [docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md#eci-013-children-and-family-members]
    record PartyName(String sourceTable, Long id, String firstName, String lastName, String middleInitial,
            LocalDateTime dob, LocalDateTime dateCreated, LocalDateTime dateModified, String modifiedBy,
            String createdBy, LocalDateTime loadDate) {}

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

    /// [docs/mappings/014_m_Tgt_C_S_ECI_Pty.md#eci-014-child-and-family-demographics]
    record PartyDemographics(String sourceTable, Long id, String childSsn, String firstName, String lastName,
            String middleInitial, LocalDateTime dob, String gestationAge, String gender, BigDecimal birthWtLb,
            BigDecimal birthWtOz, String interpretInd, String languageCd, String raceCd, LocalDateTime dateCreated,
            LocalDateTime dateModified, String modifiedBy, String createdBy, String ethnicity, Integer raceWhite,
            Integer raceAa, Integer raceAsian, Integer racePi, Integer raceAn, LocalDateTime loadDate) {}

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

    /// [docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md#eci-015-family-addresses]
    record FamilyAddress(String sourceTable, Long id, Long idFamilyAddress, String address1, String address2,
            String addressCd, String cityName, String countyName, String stateAbbrev, String zipCode, String zipSfx,
            LocalDateTime lastUpdateDate) {}

    @Query("""
            SELECT source_table, id, id_family_address, address1, address2, address_cd, city_name, county_name,
                   state_abbrev, zip_code, zip_sfx, last_update_date
            FROM v_eci_etl_src_family_address
            """)
    List<FamilyAddress> fetchFamilyAddresses();

    /// [docs/mappings/016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md#eci-016-child-and-family-identifiers]
    record PartyIdentifier(Long id, String ptyRelFk, String srcKeySfx, String altIdTp, String altIdVal,
            LocalDateTime dateCreated, LocalDateTime dateModified, String pkeySrcObject) {}

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

    /// [docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md#eci-017-family-phones-and-e-mail]
    record FamilyContact(String sourceTable, String idFamilyPhone, Long idCase, String id,
            LocalDateTime periodStartDate, String phoneEmailType, String phoneEmail, String workExt, String phoneTp,
            String usgTp, String prefLvl) {}

    @Query("""
            SELECT source_table, id_family_phone, id_case, id, period_start_date, phone_email_type, phone_email,
                   work_ext, phone_tp, usg_tp, pref_lvl
            FROM v_eci_etl_src_family_phone
            """)
    List<FamilyContact> fetchFamilyContacts();

    /// [docs/mappings/018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md#eci-018-child-family-relations]
    record FamilyRelation(String relationDirection, Long idFamily, String familyGender, Long idChild,
            String familyCd, LocalDateTime dateModified, LocalDateTime dateCreated) {}

    @Query("""
            SELECT d.relation_direction, f.id_family, f.gender AS family_gender, f.id_child,
                   TO_CHAR(f.family_cd) AS family_cd, COALESCE(f.date_modified, f.date_created) AS date_modified,
                   f.date_created
            FROM stg_eci_d_family f
            JOIN (SELECT 'From Child' relation_direction FROM dual
                  UNION ALL
                  SELECT 'To Child' FROM dual) d ON 1 = 1
            """)
    List<FamilyRelation> fetchFamilyRelations();

    // ---- lookups ------------------------------------------------------------------------------------------------

    record FamilyValidation(String sourceTable, Long idFamily, String famNameStatus, String famPhoneAndAddressSts,
            String famInactiveSts) {}

    @Query("""
            SELECT src_key AS lookup_key, deactivation_sts AS lookup_value FROM stg_eci_pty_inactive_sts
            WHERE rowid_system = 'ECI' AND deactivation_sts IS NOT NULL
            """)
    List<KeyValue> fetchInactiveStatuses();

    @Query("""
            SELECT pkey_src_object AS lookup_key, hub_state_ind AS lookup_value FROM c_b_pty_xref
            WHERE rowid_system = 'ECI'
            """)
    List<KeyNumber> fetchHubStates();

    @Query("SELECT source_table || '|' || id AS lookup_key, TO_CHAR(id) AS lookup_value FROM v_eci_etl_lu_dup_cases")
    List<KeyValue> fetchDuplicateCases();

    @Query("""
            SELECT source_table, id_family, fam_name_status, fam_phone_and_address_sts, fam_inactive_sts
            FROM v_eci_etl_lu_family_validation
            """)
    List<FamilyValidation> fetchFamilyValidations();

    @Query("SELECT TO_CHAR(id_child) AS lookup_key, gender AS lookup_value FROM stg_eci_sn_child")
    List<KeyValue> fetchChildGenders();
}
