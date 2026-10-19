package com.idq.cli.source.fss;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the FSS source tables and views read by
/// `wf_FSS_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [FssQueries]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_FSS`). Source tables have no primary key, so the
/// records carry no `@Id` and are only ever read.
///
/// `STG_FSS_PTY_INACTIVE_STS` is written by the validation mapping: see [FssTargets.InactiveStatus].
public final class FssSources {

    private FssSources() {}

    @Table("V_FSS_ETL_SRC")
    public record EtlSrc(String sourceType, LocalDateTime dtCreated, LocalDateTime dtLastUpdate,
            LocalDateTime stgUpdateDate, Long idClient, String ptySrcKey, String nmFirst, String nmLast,
            String nmMiddle, String cdSuffix, LocalDateTime dtDob, String cdGender, String languageCd,
            String cdHispanic, String ssn, BigDecimal raceAn, BigDecimal raceAsian, BigDecimal raceAa,
            BigDecimal raceWhite, BigDecimal racePi, BigDecimal raceDeclined, BigDecimal raceUnableToDetermine,
            BigDecimal raceInvalid, String addrLine1, String addrLine2, String addrCity, String addrState,
            String addrZip, String cdCnty, String nbrPhone, String nbrPhoneExt, String addrEmail, String cdReltshpToTc,
            String cdClntType, @Column("DTL__CAPXACTION") String dtlCapxaction,
            @Column("DTL__CAPXTIMESTAMP") String dtlCapxtimestamp,
            @Column("CLIENT_DTL__CAPXACTION") String clientDtlCapxaction,
            @Column("CLIENT_DTL__CAPXTIMESTAMP") String clientDtlCapxtimestamp, Long idRegistrationClient,
            Long idRegistration, String lastActiveClientRegistrationYn, String lastInactvClientYn) {}

    @Table("V_FSS_ETL_SRC_RELATIONS")
    public record EtlSrcRelations(String relationDirection, LocalDateTime dtCreated, LocalDateTime dtLastUpdate,
            LocalDateTime relnDtCreated, LocalDateTime relnDtLastUpdate, Long idClient, Long relnIdClient,
            String ptySrcKey, String relnPtySrcKey, String cdGender, String relnCdGender, String cdReltshpToTc,
            String relnCdClntType, Long idRegistrationClient, Long relnIdRegistrationClient, Long idRegistration) {}
}
