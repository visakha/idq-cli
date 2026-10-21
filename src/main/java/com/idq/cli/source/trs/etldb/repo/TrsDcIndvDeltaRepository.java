package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberDemographics;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberIdentifiers;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberSwitches;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_DC_INDV` - daily individuals; drives the demographics, identifier and switch queries (joined with
/// the MCI individuals).
public interface TrsDcIndvDeltaRepository extends Repository<TrsSources.DcIndvDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_OnGoing`: the `IdqMapInitQuery`.
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

    /// `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`: the `IdqMapInitQuery`.
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

    /// `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`: the `IdqMapInitQuery`.
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
}
