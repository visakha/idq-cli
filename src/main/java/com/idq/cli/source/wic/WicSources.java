package com.idq.cli.source.wic;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the WIC source tables and views read by
/// `wf_WIC_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [WicQueries]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_WIC`). Source tables have no primary key, so the
/// records carry no `@Id` and are only ever read.
///
/// `STG_WIC_PTY_INACTIVE_STS` is written by the validation mapping: see [WicTargets.InactiveStatus].
public final class WicSources {

    private WicSources() {}

    @Table("V_WIC_ETL_SRC")
    public record EtlSrc(String sourceTable, LocalDateTime datekey, LocalDateTime loadDate, String id, String ptySrcKey,
            String cid, String fid, String firstName, String lastName, String middleName, LocalDateTime dob,
            String gender, BigDecimal birthWtLb, BigDecimal birthWtOz, String languageCd, String ethnicity,
            BigDecimal raceWhiteInd, BigDecimal raceAaInd, BigDecimal raceAsianInd, BigDecimal racePiInd,
            BigDecimal raceAnInd, String address1, String address2, String city, String zipCode, String county,
            String phone, String email, LocalDateTime dateAddressValidFrom) {}
}
