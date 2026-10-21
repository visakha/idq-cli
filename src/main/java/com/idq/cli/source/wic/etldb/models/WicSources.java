package com.idq.cli.source.wic.etldb.models;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the WIC source tables and views read by
/// `wf_WIC_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [WicQueryRows]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_WIC`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// `STG_WIC_PTY_INACTIVE_STS` is written by the validation mapping: see [WicSources.InactiveStatus].
public final class WicSources {

    private WicSources() {}

    /// Provisional `@Id` `ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_WIC_ETL_SRC")
    public record EtlSrc(String sourceTable, LocalDateTime datekey, LocalDateTime loadDate, @Id String id,
            String ptySrcKey, String cid, String fid, String firstName, String lastName, String middleName,
            LocalDateTime dob, String gender, BigDecimal birthWtLb, BigDecimal birthWtOz, String languageCd,
            String ethnicity, BigDecimal raceWhiteInd, BigDecimal raceAaInd, BigDecimal raceAsianInd,
            BigDecimal racePiInd, BigDecimal raceAnInd, String address1, String address2, String city, String zipCode,
            String county, String phone, String email, LocalDateTime dateAddressValidFrom) {

        /// `EtlSrc.builder().sourceTable(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String sourceTable;
            private LocalDateTime datekey;
            private LocalDateTime loadDate;
            private String id;
            private String ptySrcKey;
            private String cid;
            private String fid;
            private String firstName;
            private String lastName;
            private String middleName;
            private LocalDateTime dob;
            private String gender;
            private BigDecimal birthWtLb;
            private BigDecimal birthWtOz;
            private String languageCd;
            private String ethnicity;
            private BigDecimal raceWhiteInd;
            private BigDecimal raceAaInd;
            private BigDecimal raceAsianInd;
            private BigDecimal racePiInd;
            private BigDecimal raceAnInd;
            private String address1;
            private String address2;
            private String city;
            private String zipCode;
            private String county;
            private String phone;
            private String email;
            private LocalDateTime dateAddressValidFrom;

            private Builder() {}

            public Builder sourceTable(String value) { sourceTable = value; return this; }
            public Builder datekey(LocalDateTime value) { datekey = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }
            public Builder id(String value) { id = value; return this; }
            public Builder ptySrcKey(String value) { ptySrcKey = value; return this; }
            public Builder cid(String value) { cid = value; return this; }
            public Builder fid(String value) { fid = value; return this; }
            public Builder firstName(String value) { firstName = value; return this; }
            public Builder lastName(String value) { lastName = value; return this; }
            public Builder middleName(String value) { middleName = value; return this; }
            public Builder dob(LocalDateTime value) { dob = value; return this; }
            public Builder gender(String value) { gender = value; return this; }
            public Builder birthWtLb(BigDecimal value) { birthWtLb = value; return this; }
            public Builder birthWtOz(BigDecimal value) { birthWtOz = value; return this; }
            public Builder languageCd(String value) { languageCd = value; return this; }
            public Builder ethnicity(String value) { ethnicity = value; return this; }
            public Builder raceWhiteInd(BigDecimal value) { raceWhiteInd = value; return this; }
            public Builder raceAaInd(BigDecimal value) { raceAaInd = value; return this; }
            public Builder raceAsianInd(BigDecimal value) { raceAsianInd = value; return this; }
            public Builder racePiInd(BigDecimal value) { racePiInd = value; return this; }
            public Builder raceAnInd(BigDecimal value) { raceAnInd = value; return this; }
            public Builder address1(String value) { address1 = value; return this; }
            public Builder address2(String value) { address2 = value; return this; }
            public Builder city(String value) { city = value; return this; }
            public Builder zipCode(String value) { zipCode = value; return this; }
            public Builder county(String value) { county = value; return this; }
            public Builder phone(String value) { phone = value; return this; }
            public Builder email(String value) { email = value; return this; }
            public Builder dateAddressValidFrom(LocalDateTime value) { dateAddressValidFrom = value; return this; }

            public EtlSrc build() {
                return new EtlSrc(sourceTable, datekey, loadDate, id, ptySrcKey, cid, fid, firstName, lastName,
                        middleName, dob, gender, birthWtLb, birthWtOz, languageCd, ethnicity, raceWhiteInd, raceAaInd,
                        raceAsianInd, racePiInd, raceAnInd, address1, address2, city, zipCode, county, phone, email,
                        dateAddressValidFrom);
            }
        }
    }

    @Table("STG_WIC_PTY_INACTIVE_STS")
    public record InactiveStatus(@Id String srcKey, String rowidSystem, String deactivationSts,
            LocalDateTime deactivationDt) {}

    @Table("STG_WIC_PTY_INACTIVE_LOG")
    public record InactiveLog(@Id String srcKey, String rowidSystem, String action, LocalDateTime actionDt) {}
}
