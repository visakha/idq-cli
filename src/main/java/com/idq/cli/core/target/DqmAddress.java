package com.idq.cli.core.target;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// `DQM_ADDRESS`: audit of every address sent to validation, written by all address mappings.
@Table("DQM_ADDRESS")
public record DqmAddress(
        String ptySrcKey, @Id String addrSrcKey, String srcSystem, String mdmAddrTp, LocalDateTime loadDt,
        @Column("SRC_ADDR_1") String srcAddr1, @Column("SRC_ADDR_2") String srcAddr2, String srcCity,
        String srcState, String srcPstlCd, String srcCntry, String srcCounty,
        @Column("RSLT_ADDR_1") String rsltAddr1, @Column("RSLT_ADDR_2") String rsltAddr2, String rsltCity,
        String rsltState, String rsltPstlCd, String rsltCntry, String rsltCounty, String countyFips,
        String stateFips, BigDecimal lattd, BigDecimal lngtd, String geocdStsCd, String rsdntlDlvryInd,
        String orgDesc, String orgDept, String orgNm, String bldg, String subBldg, String mlbltyScr,
        String addrdrMtchCd, BigDecimal addrdrRsltPct, String addrdrAddrTpCd, String erlyWrngCd, String cassErrCd,
        String dlvryPntVldn) {}
