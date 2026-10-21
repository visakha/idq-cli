package com.idq.cli.source.ttf.etldb.models;

import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the TTF source tables and views read by
/// `wf_TTF_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [TtfQueryRows]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_TTF`) and the rows the mock data inserts. Source
/// tables have no primary key; each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// `STG_TTF_PTY_INACTIVE_STS` is written by the validation mapping: see [TtfSources.InactiveStatus].
public final class TtfSources {

    private TtfSources() {}

    /// Provisional `@Id` `CLIENTS_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_TTF_ETL_SRC")
    public record EtlSrc(Long demographicsId, String ptySrcKey, Long year, Long month, String zip, Integer sexid,
            Integer countyid, String gestageatenrollment, String raceethnicityid, Integer ethnicity, Long submissionid,
            Integer active, String medicaidid, String firstname, String lastname, String middlename, LocalDateTime dob,
            LocalDateTime loadDate, LocalDateTime createddate, LocalDateTime updateddate, String phone,
            Long fyclientsId, Long contractid, @Id Long clientsId, String clientcode, Long contractorid,
            LocalDateTime submissionUpdateddate, LocalDateTime submitdate, LocalDateTime reportfordate,
            String clientExistsFlag) {

        /// `EtlSrc.builder().demographicsId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Long demographicsId;
            private String ptySrcKey;
            private Long year;
            private Long month;
            private String zip;
            private Integer sexid;
            private Integer countyid;
            private String gestageatenrollment;
            private String raceethnicityid;
            private Integer ethnicity;
            private Long submissionid;
            private Integer active;
            private String medicaidid;
            private String firstname;
            private String lastname;
            private String middlename;
            private LocalDateTime dob;
            private LocalDateTime loadDate;
            private LocalDateTime createddate;
            private LocalDateTime updateddate;
            private String phone;
            private Long fyclientsId;
            private Long contractid;
            private Long clientsId;
            private String clientcode;
            private Long contractorid;
            private LocalDateTime submissionUpdateddate;
            private LocalDateTime submitdate;
            private LocalDateTime reportfordate;
            private String clientExistsFlag;

            private Builder() {}

            public Builder demographicsId(Long value) { demographicsId = value; return this; }
            public Builder ptySrcKey(String value) { ptySrcKey = value; return this; }
            public Builder year(Long value) { year = value; return this; }
            public Builder month(Long value) { month = value; return this; }
            public Builder zip(String value) { zip = value; return this; }
            public Builder sexid(Integer value) { sexid = value; return this; }
            public Builder countyid(Integer value) { countyid = value; return this; }
            public Builder gestageatenrollment(String value) { gestageatenrollment = value; return this; }
            public Builder raceethnicityid(String value) { raceethnicityid = value; return this; }
            public Builder ethnicity(Integer value) { ethnicity = value; return this; }
            public Builder submissionid(Long value) { submissionid = value; return this; }
            public Builder active(Integer value) { active = value; return this; }
            public Builder medicaidid(String value) { medicaidid = value; return this; }
            public Builder firstname(String value) { firstname = value; return this; }
            public Builder lastname(String value) { lastname = value; return this; }
            public Builder middlename(String value) { middlename = value; return this; }
            public Builder dob(LocalDateTime value) { dob = value; return this; }
            public Builder loadDate(LocalDateTime value) { loadDate = value; return this; }
            public Builder createddate(LocalDateTime value) { createddate = value; return this; }
            public Builder updateddate(LocalDateTime value) { updateddate = value; return this; }
            public Builder phone(String value) { phone = value; return this; }
            public Builder fyclientsId(Long value) { fyclientsId = value; return this; }
            public Builder contractid(Long value) { contractid = value; return this; }
            public Builder clientsId(Long value) { clientsId = value; return this; }
            public Builder clientcode(String value) { clientcode = value; return this; }
            public Builder contractorid(Long value) { contractorid = value; return this; }
            public Builder submissionUpdateddate(LocalDateTime value) { submissionUpdateddate = value; return this; }
            public Builder submitdate(LocalDateTime value) { submitdate = value; return this; }
            public Builder reportfordate(LocalDateTime value) { reportfordate = value; return this; }
            public Builder clientExistsFlag(String value) { clientExistsFlag = value; return this; }

            public EtlSrc build() {
                return new EtlSrc(demographicsId, ptySrcKey, year, month, zip, sexid, countyid, gestageatenrollment,
                        raceethnicityid, ethnicity, submissionid, active, medicaidid, firstname, lastname, middlename,
                        dob, loadDate, createddate, updateddate, phone, fyclientsId, contractid, clientsId, clientcode,
                        contractorid, submissionUpdateddate, submitdate, reportfordate, clientExistsFlag);
            }
        }
    }

    @Table("STG_TTF_PTY_INACTIVE_STS")
    public record InactiveStatus(@Id String srcKey, String rowidSystem, String deactivationSts,
            LocalDateTime deactivationDt) {}

    @Table("STG_TTF_PTY_INACTIVE_LOG")
    public record InactiveLog(@Id String srcKey, String rowidSystem, String action, LocalDateTime actionDt) {}
}
