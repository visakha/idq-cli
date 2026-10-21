package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceSegment;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_CV_MCI_EDG_INDV_TOA` - type of assistance segments of the day.
public interface TrsCvMciEdgIndvToaDeltaRepository extends Repository<TrsSources.CvMciEdgIndvToaDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_Rle_TOA`: the `IdqMapInitQuery`.
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
}
