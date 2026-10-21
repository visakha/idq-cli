package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.CaseContact;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_DC_CASES` - cases of the day and their contact numbers.
public interface TrsDcCasesDeltaRepository extends Repository<TrsSources.DcCasesDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`: the `IdqMapInitQuery`.
    @Query("""
            SELECT DISTINCT i.indv_id, c.case_num, c.create_dt, c.work_ph_num, c.other_ph_num, c.email, c.ph_num,
                   c.office_num, c.work_ph_num_ext, TO_CHAR(i.indv_id) AS pty_pk
            FROM stg_trs_d_dc_cases c
            JOIN stg_trs_dc_case_indv i ON c.case_num = i.case_num
            JOIN stg_trs_valid_members vm ON TO_CHAR(i.indv_id) = vm.pty_pk
            """)
    List<CaseContact> fetchCaseContacts();
}
