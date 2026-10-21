package com.idq.cli.source.fss.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the FSS source tables and views read by
/// `wf_FSS_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [FssQueryRows]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_FSS`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// `STG_FSS_PTY_INACTIVE_STS` is written by the validation mapping: see [FssSources.InactiveStatus].
public final class FssSources {

    private FssSources() {}

    /// Provisional `@Id` `ID_CLIENT`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_FSS_ETL_SRC")
    public record EtlSrc(String sourceType, LocalDateTime dtCreated, LocalDateTime dtLastUpdate,
            LocalDateTime stgUpdateDate, @Id Long idClient, String ptySrcKey, String nmFirst, String nmLast,
            String nmMiddle, String cdSuffix, LocalDateTime dtDob, String cdGender, String languageCd,
            String cdHispanic, String ssn, BigDecimal raceAn, BigDecimal raceAsian, BigDecimal raceAa,
            BigDecimal raceWhite, BigDecimal racePi, BigDecimal raceDeclined, BigDecimal raceUnableToDetermine,
            BigDecimal raceInvalid, String addrLine1, String addrLine2, String addrCity, String addrState,
            String addrZip, String cdCnty, String nbrPhone, String nbrPhoneExt, String addrEmail, String cdReltshpToTc,
            String cdClntType, @Column("DTL__CAPXACTION") String dtlCapxaction,
            @Column("DTL__CAPXTIMESTAMP") String dtlCapxtimestamp,
            @Column("CLIENT_DTL__CAPXACTION") String clientDtlCapxaction,
            @Column("CLIENT_DTL__CAPXTIMESTAMP") String clientDtlCapxtimestamp, Long idRegistrationClient,
            Long idRegistration, String lastActiveClientRegistrationYn, String lastInactvClientYn) {

        /// `EtlSrc.builder().sourceType(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String sourceType;
            private LocalDateTime dtCreated;
            private LocalDateTime dtLastUpdate;
            private LocalDateTime stgUpdateDate;
            private Long idClient;
            private String ptySrcKey;
            private String nmFirst;
            private String nmLast;
            private String nmMiddle;
            private String cdSuffix;
            private LocalDateTime dtDob;
            private String cdGender;
            private String languageCd;
            private String cdHispanic;
            private String ssn;
            private BigDecimal raceAn;
            private BigDecimal raceAsian;
            private BigDecimal raceAa;
            private BigDecimal raceWhite;
            private BigDecimal racePi;
            private BigDecimal raceDeclined;
            private BigDecimal raceUnableToDetermine;
            private BigDecimal raceInvalid;
            private String addrLine1;
            private String addrLine2;
            private String addrCity;
            private String addrState;
            private String addrZip;
            private String cdCnty;
            private String nbrPhone;
            private String nbrPhoneExt;
            private String addrEmail;
            private String cdReltshpToTc;
            private String cdClntType;
            private String dtlCapxaction;
            private String dtlCapxtimestamp;
            private String clientDtlCapxaction;
            private String clientDtlCapxtimestamp;
            private Long idRegistrationClient;
            private Long idRegistration;
            private String lastActiveClientRegistrationYn;
            private String lastInactvClientYn;

            private Builder() {}

            public Builder sourceType(String value) { sourceType = value; return this; }
            public Builder dtCreated(LocalDateTime value) { dtCreated = value; return this; }
            public Builder dtLastUpdate(LocalDateTime value) { dtLastUpdate = value; return this; }
            public Builder stgUpdateDate(LocalDateTime value) { stgUpdateDate = value; return this; }
            public Builder idClient(Long value) { idClient = value; return this; }
            public Builder ptySrcKey(String value) { ptySrcKey = value; return this; }
            public Builder nmFirst(String value) { nmFirst = value; return this; }
            public Builder nmLast(String value) { nmLast = value; return this; }
            public Builder nmMiddle(String value) { nmMiddle = value; return this; }
            public Builder cdSuffix(String value) { cdSuffix = value; return this; }
            public Builder dtDob(LocalDateTime value) { dtDob = value; return this; }
            public Builder cdGender(String value) { cdGender = value; return this; }
            public Builder languageCd(String value) { languageCd = value; return this; }
            public Builder cdHispanic(String value) { cdHispanic = value; return this; }
            public Builder ssn(String value) { ssn = value; return this; }
            public Builder raceAn(BigDecimal value) { raceAn = value; return this; }
            public Builder raceAsian(BigDecimal value) { raceAsian = value; return this; }
            public Builder raceAa(BigDecimal value) { raceAa = value; return this; }
            public Builder raceWhite(BigDecimal value) { raceWhite = value; return this; }
            public Builder racePi(BigDecimal value) { racePi = value; return this; }
            public Builder raceDeclined(BigDecimal value) { raceDeclined = value; return this; }
            public Builder raceUnableToDetermine(BigDecimal value) { raceUnableToDetermine = value; return this; }
            public Builder raceInvalid(BigDecimal value) { raceInvalid = value; return this; }
            public Builder addrLine1(String value) { addrLine1 = value; return this; }
            public Builder addrLine2(String value) { addrLine2 = value; return this; }
            public Builder addrCity(String value) { addrCity = value; return this; }
            public Builder addrState(String value) { addrState = value; return this; }
            public Builder addrZip(String value) { addrZip = value; return this; }
            public Builder cdCnty(String value) { cdCnty = value; return this; }
            public Builder nbrPhone(String value) { nbrPhone = value; return this; }
            public Builder nbrPhoneExt(String value) { nbrPhoneExt = value; return this; }
            public Builder addrEmail(String value) { addrEmail = value; return this; }
            public Builder cdReltshpToTc(String value) { cdReltshpToTc = value; return this; }
            public Builder cdClntType(String value) { cdClntType = value; return this; }
            public Builder dtlCapxaction(String value) { dtlCapxaction = value; return this; }
            public Builder dtlCapxtimestamp(String value) { dtlCapxtimestamp = value; return this; }
            public Builder clientDtlCapxaction(String value) { clientDtlCapxaction = value; return this; }
            public Builder clientDtlCapxtimestamp(String value) { clientDtlCapxtimestamp = value; return this; }
            public Builder idRegistrationClient(Long value) { idRegistrationClient = value; return this; }
            public Builder idRegistration(Long value) { idRegistration = value; return this; }
            public Builder lastActiveClientRegistrationYn(String value) {
                lastActiveClientRegistrationYn = value;
                return this;
            }
            public Builder lastInactvClientYn(String value) { lastInactvClientYn = value; return this; }

            public EtlSrc build() {
                return new EtlSrc(sourceType, dtCreated, dtLastUpdate, stgUpdateDate, idClient, ptySrcKey, nmFirst,
                        nmLast, nmMiddle, cdSuffix, dtDob, cdGender, languageCd, cdHispanic, ssn, raceAn, raceAsian,
                        raceAa, raceWhite, racePi, raceDeclined, raceUnableToDetermine, raceInvalid, addrLine1,
                        addrLine2, addrCity, addrState, addrZip, cdCnty, nbrPhone, nbrPhoneExt, addrEmail,
                        cdReltshpToTc, cdClntType, dtlCapxaction, dtlCapxtimestamp, clientDtlCapxaction,
                        clientDtlCapxtimestamp, idRegistrationClient, idRegistration, lastActiveClientRegistrationYn,
                        lastInactvClientYn);
            }
        }
    }

    /// Provisional `@Id` `ID_CLIENT`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_FSS_ETL_SRC_RELATIONS")
    public record EtlSrcRelations(String relationDirection, LocalDateTime dtCreated, LocalDateTime dtLastUpdate,
            LocalDateTime relnDtCreated, LocalDateTime relnDtLastUpdate, @Id Long idClient, Long relnIdClient,
            String ptySrcKey, String relnPtySrcKey, String cdGender, String relnCdGender, String cdReltshpToTc,
            String relnCdClntType, Long idRegistrationClient, Long relnIdRegistrationClient, Long idRegistration) {

        /// `EtlSrcRelations.builder().relationDirection(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String relationDirection;
            private LocalDateTime dtCreated;
            private LocalDateTime dtLastUpdate;
            private LocalDateTime relnDtCreated;
            private LocalDateTime relnDtLastUpdate;
            private Long idClient;
            private Long relnIdClient;
            private String ptySrcKey;
            private String relnPtySrcKey;
            private String cdGender;
            private String relnCdGender;
            private String cdReltshpToTc;
            private String relnCdClntType;
            private Long idRegistrationClient;
            private Long relnIdRegistrationClient;
            private Long idRegistration;

            private Builder() {}

            public Builder relationDirection(String value) { relationDirection = value; return this; }
            public Builder dtCreated(LocalDateTime value) { dtCreated = value; return this; }
            public Builder dtLastUpdate(LocalDateTime value) { dtLastUpdate = value; return this; }
            public Builder relnDtCreated(LocalDateTime value) { relnDtCreated = value; return this; }
            public Builder relnDtLastUpdate(LocalDateTime value) { relnDtLastUpdate = value; return this; }
            public Builder idClient(Long value) { idClient = value; return this; }
            public Builder relnIdClient(Long value) { relnIdClient = value; return this; }
            public Builder ptySrcKey(String value) { ptySrcKey = value; return this; }
            public Builder relnPtySrcKey(String value) { relnPtySrcKey = value; return this; }
            public Builder cdGender(String value) { cdGender = value; return this; }
            public Builder relnCdGender(String value) { relnCdGender = value; return this; }
            public Builder cdReltshpToTc(String value) { cdReltshpToTc = value; return this; }
            public Builder relnCdClntType(String value) { relnCdClntType = value; return this; }
            public Builder idRegistrationClient(Long value) { idRegistrationClient = value; return this; }
            public Builder relnIdRegistrationClient(Long value) { relnIdRegistrationClient = value; return this; }
            public Builder idRegistration(Long value) { idRegistration = value; return this; }

            public EtlSrcRelations build() {
                return new EtlSrcRelations(relationDirection, dtCreated, dtLastUpdate, relnDtCreated, relnDtLastUpdate,
                        idClient, relnIdClient, ptySrcKey, relnPtySrcKey, cdGender, relnCdGender, cdReltshpToTc,
                        relnCdClntType, idRegistrationClient, relnIdRegistrationClient, idRegistration);
            }
        }
    }

    @Table("STG_FSS_PTY_INACTIVE_STS")
    public record InactiveStatus(@Id String srcKey, String rowidSystem, String deactivationSts,
            LocalDateTime deactivationDt) {}

    @Table("STG_FSS_PTY_INACTIVE_LOG")
    public record InactiveLog(@Id String srcKey, String rowidSystem, String action, LocalDateTime actionDt) {}
}
