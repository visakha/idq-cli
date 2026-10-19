package com.idq.cli.source.trs;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// Named-query interface of the TRS workflow (`wf_TRS_Stage_Load_1_Ongoing`).
///
/// Each `IdqMapInitQuery` is the source SQL override of its mapping with stale hard-coded test filters removed and
/// IDQ parameters (`$MCI_TBL_SRC`, `$DC_INDV_TBL_SRC`, `$INDV_ID_ALT_ID_TP`) replaced by their values. The section
/// of the mapping document is linked on each method.
public interface TrsQueries extends Repository<TrsTargets.ValidMember, String> {

    /// [docs/mappings/001_m_Tgt_C_S_TRS_Pty_OnGoing.md#trs-001-valid-member-demographics]
    record MemberDemographics(Long indvId, String firstName, String midName, String lastName, String sufxName,
            String prefixName, String genderCd, String raceCd, String ethnicityCd, String ssaValSw, String fileClSw,
            LocalDateTime dobDt, LocalDateTime createDt, String srcTbl, LocalDateTime deathDt) {}

    @Query("""
            WITH new_valid_indvs AS (
                SELECT DISTINCT indv_id FROM stg_trs_d_cv_mci_edg_indv_toa WHERE conversion_ind = 'C'
                UNION
                SELECT DISTINCT indv_id FROM stg_trs_d_dc_indv
                WHERE file_clearance_sw = 'Y' AND inactive_ind = 'N' AND delete_sw = 'N'
                UNION
                SELECT DISTINCT indv_id FROM stg_trs_d_cv_dc_mci_indv WHERE inactive_ind = 'N'
                UNION
                SELECT DISTINCT indv_id FROM stg_trs_valid_members
                MINUS
                SELECT DISTINCT indv_id FROM stg_trs_d_dc_indv WHERE inactive_ind = 'Y' OR delete_sw = 'Y'
                MINUS
                SELECT DISTINCT indv_id FROM stg_trs_d_cv_dc_mci_indv WHERE inactive_ind = 'Y'
                MINUS
                SELECT indv_id FROM stg_trs_deactived_members
            ),
            all_indv AS (
                SELECT indv_id, first_name, mid_name, last_name, sufx_name, prefix_name, gender_cd, race_cd,
                       ethnicity_cd, NULL AS ssa_val_sw, NULL AS file_cl_sw, dob_dt, NULL AS death_dt, create_dt,
                       'MCI' AS src_tbl
                FROM stg_trs_d_cv_dc_mci_indv
                UNION ALL
                SELECT indv_id, first_name, mid_name, last_name, sufx_name, prefix_name, gender_cd, race_cd,
                       ethnicity_cd, ssa_validation_sw, file_clearance_sw, dob_dt, death_dt, create_dt,
                       'DC_INDV' AS src_tbl
                FROM stg_trs_d_dc_indv
            )
            SELECT DISTINCT a.indv_id, RTRIM(LTRIM(a.first_name)) AS first_name, RTRIM(LTRIM(a.mid_name)) AS mid_name,
                   RTRIM(LTRIM(a.last_name)) AS last_name, RTRIM(a.sufx_name) AS sufx_name,
                   RTRIM(a.prefix_name) AS prefix_name, a.gender_cd, a.race_cd, a.ethnicity_cd, a.ssa_val_sw,
                   a.file_cl_sw, a.dob_dt, a.create_dt, a.src_tbl, a.death_dt
            FROM all_indv a
            JOIN new_valid_indvs f ON f.indv_id = a.indv_id
            ORDER BY a.indv_id, a.src_tbl
            """)
    List<MemberDemographics> fetchMemberDemographics();

    /// `lkp_Stg_TRS_Valid_Members` of mapping 001.
    @Query("SELECT PTY_PK FROM STG_TRS_VALID_MEMBERS")
    List<String> fetchValidMemberKeys();

    /// [docs/mappings/002_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md#trs-002-authorized-representative-flags]
    record AuthorizedRepresentative(Long indvId, String arFlag, LocalDateTime effBeginDt, LocalDateTime effEndDt,
            LocalDateTime createDt) {}

    @Query("""
            SELECT DISTINCT a.indv_id, a.ar_flag, a.eff_begin_dt, a.eff_end_dt, a.create_dt
            FROM (
                SELECT ed.indv_id, 'Y' ar_flag, ed.elig_eff_begin_dt eff_begin_dt, ed.elig_eff_end_dt eff_end_dt,
                       p.create_dt
                FROM stg_trs_d_dc_primary_payee p
                JOIN stg_trs_cv_ed_mci_edg_indv ed
                  ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
                JOIN stg_trs_dc_cases c ON p.case_num = c.case_num
                WHERE (p.addr_type_cd = 'MA' OR p.addr_type_cd IS NULL) AND p.alt_payee_exists_sw = 'Y'
                  AND c.authrep_verf_cd IN ('CS', 'FH', 'LD', 'OA') AND c.sent_authrep_sw = 'Y'
                UNION ALL
                SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
                FROM stg_trs_d_dc_cases c
                JOIN stg_trs_dc_primary_payee p ON p.case_num = c.case_num
                JOIN stg_trs_cv_ed_mci_edg_indv ed
                  ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
                WHERE (p.addr_type_cd = 'MA' OR p.addr_type_cd IS NULL) AND p.alt_payee_exists_sw = 'Y'
                  AND c.authrep_verf_cd IN ('CS', 'FH', 'LD', 'OA') AND c.sent_authrep_sw = 'Y'
                UNION ALL
                SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
                FROM stg_trs_dc_cases c
                JOIN stg_trs_dc_primary_payee p ON p.case_num = c.case_num
                JOIN stg_trs_d_cv_ed_mci_edg_indv ed
                  ON p.case_num = ed.case_num AND p.edg_num = ed.edg_num AND ed.elig_eff_end_dt IS NULL
                WHERE (p.addr_type_cd = 'MA' OR p.addr_type_cd IS NULL) AND p.alt_payee_exists_sw = 'Y'
                  AND c.authrep_verf_cd IN ('CS', 'FH', 'LD', 'OA') AND c.sent_authrep_sw = 'Y'
                UNION ALL
                SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt)
                FROM stg_trs_d_cv_ed_mci_edg_indv ed
                LEFT JOIN stg_trs_dc_primary_payee p
                  ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
                 AND (p.addr_type_cd = 'MA' OR p.addr_type_cd IS NULL) AND p.alt_payee_exists_sw = 'Y'
                 AND p.edg_num IS NULL
                JOIN stg_trs_dc_cases c ON ed.case_num = c.case_num
                JOIN stg_trs_dc_case_indv ci ON c.case_num = ci.case_num
                WHERE c.authrep_verf_cd IN ('CS', 'FH', 'LD', 'OA') AND c.sent_authrep_sw = 'Y'
                UNION ALL
                SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
                FROM stg_trs_cv_ed_mci_edg_indv ed
                JOIN stg_trs_d_dc_primary_payee p
                  ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
                 AND (p.addr_type_cd = 'MA' OR p.addr_type_cd IS NULL) AND p.alt_payee_exists_sw = 'Y'
                 AND p.edg_num IS NULL
                JOIN stg_trs_dc_cases c ON ed.case_num = c.case_num
                JOIN stg_trs_dc_case_indv ci ON c.case_num = ci.case_num
                WHERE c.authrep_verf_cd IN ('CS', 'FH', 'LD', 'OA') AND c.sent_authrep_sw = 'Y'
                UNION ALL
                SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt)
                FROM stg_trs_cv_ed_mci_edg_indv ed
                LEFT JOIN stg_trs_dc_primary_payee p
                  ON ed.case_num = p.case_num AND ed.edg_num = p.edg_num AND ed.elig_eff_end_dt IS NULL
                 AND (p.addr_type_cd = 'MA' OR p.addr_type_cd IS NULL) AND p.alt_payee_exists_sw = 'Y'
                 AND p.edg_num IS NULL
                JOIN stg_trs_d_dc_cases c ON ed.case_num = c.case_num
                JOIN stg_trs_dc_case_indv ci ON c.case_num = ci.case_num
                WHERE c.authrep_verf_cd IN ('CS', 'FH', 'LD', 'OA') AND c.sent_authrep_sw = 'Y'
            ) a
            JOIN stg_trs_valid_members im ON TO_CHAR(a.indv_id) = im.pty_pk
            ORDER BY a.indv_id, a.eff_begin_dt, a.eff_end_dt
            """)
    List<AuthorizedRepresentative> fetchAuthorizedRepresentatives();

    /// [docs/mappings/003_m_Tgt_C_S_TRS_Pty_Nm.md#trs-003-member-aliases]
    record MemberAlias(Long indvId, String pkeyPty, String firstName, String midName, String lastName,
            String sufxName, String prefixName, LocalDateTime createDt, Long sequenceNum) {}

    @Query("""
            SELECT DISTINCT a.indv_id, a.pkey_pty, RTRIM(LTRIM(a.first_name)) AS first_name,
                   RTRIM(LTRIM(a.mid_name)) AS mid_name, RTRIM(LTRIM(a.last_name)) AS last_name,
                   RTRIM(a.sufx_name) AS sufx_name, RTRIM(a.prefix_name) AS prefix_name, a.create_dt, a.sequence_num
            FROM (
                SELECT indv_id, TO_CHAR(indv_id) AS pkey_pty, first_name, mid_name, last_name, sufx_name,
                       prefix_name, create_dt, sequence_num
                FROM stg_trs_d_cv_dc_mci_alias
                UNION ALL
                SELECT indv_id, TO_CHAR(indv_id) || '|DC_INDV', first_name, mid_name, last_name, sufx_name,
                       prefix_name, create_dt, seq_num
                FROM stg_trs_d_dc_alias
            ) a
            JOIN stg_trs_valid_members vm ON a.pkey_pty = vm.pty_pk
            """)
    List<MemberAlias> fetchMemberAliases();

    /// [docs/mappings/004_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md#trs-004-member-ssn-and-ids]
    record MemberIdentifiers(String ptyPkey, String memberId, LocalDateTime startDt, Long ssn, String cvInd) {}

    @Query("""
            WITH all_indv AS (
                SELECT DISTINCT TO_CHAR(indv_id) AS pty_pkey, indv_id AS member_id, create_dt, ssn, '1' cv_ind
                FROM stg_trs_d_cv_dc_mci_indv
                UNION ALL
                SELECT DISTINCT TO_CHAR(indv_id) || '|DC_INDV', indv_id, create_dt, ssn, NULL
                FROM stg_trs_d_dc_indv
                UNION ALL
                SELECT DISTINCT TO_CHAR(old_indv_id), mrg.indv_id, mrg.create_dt, NULL, NULL
                FROM stg_trs_d_cv_dc_mrg_sprt_indv mrg
                WHERE type_cd = 'ME'
            ),
            de_dup_indv AS (
                SELECT pty_pkey, TO_CHAR(member_id) AS member_id, create_dt AS start_dt, ssn, cv_ind,
                       ROW_NUMBER() OVER (PARTITION BY pty_pkey ORDER BY LENGTH(ssn) DESC, create_dt DESC) key_rn
                FROM all_indv
                JOIN stg_trs_valid_members vm ON all_indv.pty_pkey = vm.pty_pk
            )
            SELECT pty_pkey, member_id, start_dt, ssn, cv_ind FROM de_dup_indv WHERE key_rn = 1
            """)
    List<MemberIdentifiers> fetchMemberIdentifiers();

    /// `lkp_Valid_SSN` of mapping 004: SSA-validated SSNs per individual.
    record ValidSsn(Long indvId, Long ssn) {}

    @Query("""
            SELECT DISTINCT indv_id, ssn FROM stg_trs_h_dc_indv WHERE ssa_validation_sw = 'Y' AND ssn > 0
            """)
    List<ValidSsn> fetchValidSsns();

    /// [docs/mappings/005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md#trs-005-managed-care-plans]
    record ManagedCarePlan(Long indvId, LocalDateTime beginDt, String mcPlan, Long historySeq, LocalDateTime endDt,
            LocalDateTime createDt) {}

    @Query("""
            SELECT DISTINCT m.indv_id, m.begin_dt, m.mc_plan, m.history_seq, m.end_dt, m.create_dt
            FROM stg_trs_d_in_managed_care m
            JOIN stg_trs_valid_members vm ON m.indv_id = vm.indv_id AND vm.src_tbl = 'MCI'
            WHERE m.mc_plan IS NOT NULL AND (m.begin_dt < m.end_dt OR m.end_dt IS NULL)
            ORDER BY m.indv_id, m.mc_plan, m.begin_dt, m.end_dt
            """)
    List<ManagedCarePlan> fetchManagedCarePlans();

    /// [docs/mappings/006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md#trs-006-case-phones-and-e-mail]
    record CaseContact(Long indvId, Long caseNum, LocalDateTime createDt, String workPhNum, String otherPhNum,
            String email, String phNum, String officeNum, String workPhNumExt, String ptyPk) {}

    @Query("""
            SELECT DISTINCT i.indv_id, c.case_num, c.create_dt, c.work_ph_num, c.other_ph_num, c.email, c.ph_num,
                   c.office_num, c.work_ph_num_ext, TO_CHAR(i.indv_id) AS pty_pk
            FROM stg_trs_d_dc_cases c
            JOIN stg_trs_dc_case_indv i ON c.case_num = i.case_num
            JOIN stg_trs_valid_members vm ON TO_CHAR(i.indv_id) = vm.pty_pk
            """)
    List<CaseContact> fetchCaseContacts();

    /// [docs/mappings/007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md#trs-007-member-switches]
    record MemberSwitches(Long indvId, String fileClearanceSw, String ssaValidationSw, LocalDateTime effBeginDt,
            String twConvertInd, String ltcConvertInd, String ptyPk, LocalDateTime createDt, String srcTbl) {}

    @Query("""
            WITH daily_indv AS (
                SELECT dc.indv_id, dc.file_clearance_sw, dc.ssa_validation_sw, dc.create_dt AS eff_begin_dt,
                       NULL AS tw_convert_ind, NULL AS ltc_convert_ind, TO_CHAR(dc.indv_id) || '|DC_INDV' AS pty_pk,
                       create_dt, 'DC_INDV' src_tbl,
                       ROW_NUMBER() OVER (PARTITION BY indv_id ORDER BY create_dt DESC) key_rn
                FROM stg_trs_d_dc_indv dc
                UNION
                SELECT indv_id, NULL, NULL, create_dt, tw_convert_ind, ltc_convert_ind, TO_CHAR(indv_id), create_dt,
                       'MCI', ROW_NUMBER() OVER (PARTITION BY indv_id ORDER BY create_dt DESC)
                FROM stg_trs_d_cv_dc_mci_indv cv
            )
            SELECT dly.indv_id, dly.file_clearance_sw, dly.ssa_validation_sw, dly.eff_begin_dt, dly.tw_convert_ind,
                   dly.ltc_convert_ind, dly.pty_pk, dly.create_dt, dly.src_tbl
            FROM daily_indv dly
            JOIN stg_trs_valid_members im ON dly.indv_id = im.indv_id AND dly.src_tbl = im.src_tbl
            WHERE key_rn = 1
            """)
    List<MemberSwitches> fetchMemberSwitches();

    /// [docs/mappings/008_m_Tgt_C_S_TRS_Pty_Rle_TOA.md#trs-008-type-of-assistance-segments]
    record AssistanceSegment(String indvId, String typeOfAssistanceCd, LocalDateTime beginDt, LocalDateTime endDt,
            String srcTbl, String ptyPk, Long edgNum, Long caseNum, Long mciCreateSeq, String programCd,
            String partStatusCd, String systemCd, LocalDateTime convertDt, LocalDateTime createDt) {}

    @Query("""
            WITH toa_src AS (
                SELECT TO_CHAR(toa.indv_id) AS indv_id, type_of_assistance_cd, elig_eff_begin_dt AS begin_dt,
                       elig_eff_end_dt AS end_dt, 'MCI_EDG_INDV' AS src_tbl,
                       ROW_NUMBER() OVER (PARTITION BY toa.indv_id || '|' || toa.edg_num || '|' || toa.program_cd
                                          || '|' || toa.mci_create_seq ORDER BY toa.create_dt DESC) AS key_rn,
                       TO_CHAR(toa.indv_id) AS pty_pk, edg_num, case_num, mci_create_seq, program_cd, part_status_cd,
                       system_cd, convert_dt, toa.create_dt
                FROM stg_trs_d_cv_mci_edg_indv_toa toa
                JOIN stg_trs_valid_members vm ON TO_CHAR(toa.indv_id) = vm.pty_pk
                WHERE type_of_assistance_cd IS NOT NULL AND (conversion_ind IS NULL OR conversion_ind = 'C')
            )
            SELECT indv_id, type_of_assistance_cd, begin_dt, end_dt, src_tbl, pty_pk, edg_num, case_num,
                   mci_create_seq, program_cd, part_status_cd, system_cd, convert_dt, create_dt
            FROM toa_src
            WHERE key_rn = 1
            """)
    List<AssistanceSegment> fetchAssistanceSegments();

    /// [docs/mappings/009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md#trs-009-member-relationships]
    record MemberRelationship(Long indvId, Long refIndvId, LocalDateTime effBeginDt, LocalDateTime effEndDt,
            String histNavInd, String relationshipTypeCd, String ptyPkey, String refPtyPkey, String ptyAltIdTp,
            LocalDateTime createDt, LocalDateTime updateDt) {}

    @Query("""
            WITH min_pk AS (
                SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
            )
            SELECT rel.indv_id, rel.ref_indv_id, rel.eff_begin_dt, rel.eff_end_dt, rel.hist_nav_ind,
                   rel.relationship_type_cd, pk1.pty_pk AS pty_pkey, pk2.pty_pk AS ref_pty_pkey,
                   '007' AS pty_alt_id_tp, rel.create_dt, rel.update_dt
            FROM stg_trs_d_dc_relationships rel
            JOIN min_pk pk1 ON rel.indv_id = pk1.indv_id
            JOIN min_pk pk2 ON rel.ref_indv_id = pk2.indv_id
            ORDER BY rel.indv_id, rel.eff_end_dt
            """)
    List<MemberRelationship> fetchMemberRelationships();

    /// [docs/mappings/010_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md#trs-010-member-primary-care-providers]
    record PrimaryCareProvider(Long indvId, Long historySeq, String mcProgCode, LocalDateTime beginDt,
            LocalDateTime createDt, String providerNum, LocalDateTime endDt, String ptyPk) {}

    @Query("""
            WITH min_pk AS (
                SELECT indv_id, MIN(pty_pk) pty_pk FROM stg_trs_valid_members GROUP BY indv_id
            )
            SELECT mc.indv_id, mc.history_seq, mc.mc_prog_code, mc.begin_dt, mc.create_dt, mc.provider_num,
                   mc.end_dt, vm.pty_pk
            FROM stg_trs_d_in_managed_care mc
            JOIN min_pk vm ON mc.indv_id = vm.indv_id
            WHERE mc.provider_num IS NOT NULL
            ORDER BY mc.indv_id, mc.end_dt
            """)
    List<PrimaryCareProvider> fetchPrimaryCareProviders();

    /// `Lookup_C_B_PTY_RLE_ALT_ID` of mapping 010: provider TPI (`ALT_ID_TP 006`) to its newest active C21 source key.
    record ProviderKey(String altIdVal, String pkeySrcObject) {}

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

    /// [docs/mappings/011_m_Tgt_C_S_TRS_Addr_1.md#trs-011-distinct-member-addresses]
    record DistinctAddress(String addrId, String addrStNum, String addrStNumFrac, String addrStNm, String addrAptNum,
            String addrLine, String addrCity, String addrStateCd, String addrZip5, String addrZip4,
            String addrDwellingTypeCd, String addrStTypeCd, String addrStDirCd) {}

    @Query("""
            SELECT DISTINCT
                   a.addr_st_num || '|' || a.addr_st_num_frac || '|' || a.addr_st_nm || '|' || a.addr_st_dir_cd || '|'
                   || a.addr_st_type_cd || '|' || a.addr_dwelling_type_cd || '|' || a.addr_apt_num || '|'
                   || a.addr_line || '|' || a.addr_city || '|' || a.addr_state_cd || '|' || a.addr_zip5 || '|'
                   || a.addr_zip4 AS addr_id,
                   a.addr_st_num, a.addr_st_num_frac, a.addr_st_nm, a.addr_apt_num, a.addr_line, a.addr_city,
                   a.addr_state_cd, a.addr_zip5, a.addr_zip4, a.addr_dwelling_type_cd, a.addr_st_type_cd,
                   a.addr_st_dir_cd
            FROM stg_trs_d_indv_addr a
            """)
    List<DistinctAddress> fetchDistinctAddresses();

    /// [docs/mappings/012_m_Tgt_C_S_TRS_Addr_2.md#trs-012-member-address-assignments]
    record AddressAssignment(Long indvId, Long caseNum, Long edgNum, String ptyPk, String addrTypeCd,
            LocalDateTime createDt, LocalDateTime effBeginDt, LocalDateTime effEndDt, String addrId,
            String addrLn1, String addrLn2, String bldngNm, String flrNum, String city, String county, String state,
            String cntryCd, String pstlCd, String pstlCdExt, BigDecimal lattd, BigDecimal lngtd, String vldtnMsg,
            String vldtnDesc, String mlbltyScr, String addrTpCd, String orgDesc, String orgDept, String orgNm,
            String bldgNmbr, String subBldgNm, String subBldgDesc, String geocdStsCd, String rsdntlDlvryInd,
            BigDecimal addrdrRsltPct, String erlyWrngCd, String cassErrCd, String dlvryPntVldn, String srcAddrLn1,
            String srcAddrLn2, String srcCity, String srcCounty, String srcState, String srcCntry, String srcPstlCd,
            String srcPstlCdExt) {}

    @Query("""
            WITH addr_de_dup AS (
                SELECT indv_id, case_num, edg_num, addr_type_cd,
                       a.addr_st_num || '|' || a.addr_st_num_frac || '|' || a.addr_st_nm || '|' || addr_st_dir_cd
                       || '|' || addr_st_type_cd || '|' || addr_dwelling_type_cd || '|' || a.addr_apt_num || '|'
                       || a.addr_line || '|' || a.addr_city || '|' || a.addr_state_cd || '|' || a.addr_zip5 || '|'
                       || a.addr_zip4 AS addr_id,
                       GREATEST(create_dt, NVL(update_dt, create_dt)) create_dt, eff_begin_dt, eff_end_dt,
                       ROW_NUMBER() OVER (PARTITION BY indv_id, addr_type_cd, case_num, edg_num
                                          ORDER BY GREATEST(create_dt, NVL(update_dt, create_dt)) DESC,
                                                   eff_begin_dt DESC) key_rn
                FROM stg_trs_d_indv_addr a
            )
            SELECT a.indv_id, a.case_num, a.edg_num, vm.pty_pk, a.addr_type_cd, a.create_dt, a.eff_begin_dt,
                   a.eff_end_dt, u.addr_id, u.addr_ln_1 AS addr_ln1, u.addr_ln_2 AS addr_ln2, u.bldng_nm, u.flr_num,
                   u.city, u.county, u.state, u.cntry_cd, u.pstl_cd, u.pstl_cd_ext, u.lattd, u.lngtd, u.vldtn_msg,
                   u.vldtn_desc, u.mlblty_scr, u.addr_tp_cd, u.org_desc, u.org_dept, u.org_nm, u.bldg_nmbr,
                   u.sub_bldg_nm, u.sub_bldg_desc, u.geocd_sts_cd, u.rsdntl_dlvry_ind, u.addrdr_rslt_pct,
                   u.erly_wrng_cd, u.cass_err_cd, u.dlvry_pnt_vldn, u.src_addr_ln_1 AS src_addr_ln1,
                   u.src_addr_ln_2 AS src_addr_ln2, u.src_city, u.src_county, u.src_state, u.src_cntry, u.src_pstl_cd,
                   u.src_pstl_cd_ext
            FROM addr_de_dup a
            JOIN stg_trs_d_unq_addr u ON a.addr_id = u.addr_id
            JOIN stg_trs_valid_members vm ON a.indv_id = vm.indv_id
            WHERE key_rn = 1
            """)
    List<AddressAssignment> fetchAddressAssignments();
}
