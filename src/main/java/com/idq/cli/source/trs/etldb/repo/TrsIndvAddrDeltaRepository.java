package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AddressAssignment;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.DistinctAddress;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_D_INDV_ADDR` - individual addresses of the day.
public interface TrsIndvAddrDeltaRepository extends Repository<TrsSources.IndvAddrDelta, BigDecimal> {

    /// `m_Tgt_C_S_TRS_Addr_1`: the `IdqMapInitQuery`.
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

    /// `m_Tgt_C_S_TRS_Addr_2`: the `IdqMapInitQuery`.
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
