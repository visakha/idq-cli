package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AuthorizedRepresentative;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_DC_PRIMARY_PAYEE` - primary payees of the day, joined with cases and EDG individuals.
public interface TrsDcPrimaryPayeeDeltaRepository extends Repository<TrsSources.DcPrimaryPayeeDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`: the `IdqMapInitQuery`.
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
}
