package com.idq.cli.source.cre.etldb.models;

import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the CRE source tables read by
/// `wf_CRE_Stage_Load_Ongoing`, and the merge table the workflow writes.
///
/// The mapping reads through its `IdqMapInitQuery` record in [CreQueryRows]; these entities are the raw-table view
/// used by the audit reports (`adhoc_runs_CRE`) and the rows the mock data inserts. Source tables have no primary key;
/// each record carries a provisional `@Id` because Spring Data JDBC needs one to insert.
///
/// `CRE_SRC_MRG` is written by the mapping (the CARE case moves MDM has not merged yet): see [CreSources.SourceMerge].
public final class CreSources {

    private CreSources() {}

    /// Provisional `@Id` `CARE_ID`: the table has no primary key, Spring Data JDBC needs one.
    /// The daily CARE client delta; `MAINT_FLAG` `D` marks a maintained (moved or deleted) case.
    @Table("STG_CRE_D_CARE_CLIENTS")
    public record CareClientsDelta(@Id String careId, LocalDateTime careLastupDt, String firstnm, String lastnm,
            String lastSuf, LocalDateTime birthDt, String sex, String street, String city, String cnty, String state,
            String zip, String zipsuf, String phone, String recipNo, String maintFlag, String ssn,
            LocalDateTime insertDate, String fedeth, String race, LocalDateTime extractDt) {

        /// `CareClientsDelta.builder().careId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String careId;
            private LocalDateTime careLastupDt;
            private String firstnm;
            private String lastnm;
            private String lastSuf;
            private LocalDateTime birthDt;
            private String sex;
            private String street;
            private String city;
            private String cnty;
            private String state;
            private String zip;
            private String zipsuf;
            private String phone;
            private String recipNo;
            private String maintFlag;
            private String ssn;
            private LocalDateTime insertDate;
            private String fedeth;
            private String race;
            private LocalDateTime extractDt;

            private Builder() {}

            public Builder careId(String value) { careId = value; return this; }
            public Builder careLastupDt(LocalDateTime value) { careLastupDt = value; return this; }
            public Builder firstnm(String value) { firstnm = value; return this; }
            public Builder lastnm(String value) { lastnm = value; return this; }
            public Builder lastSuf(String value) { lastSuf = value; return this; }
            public Builder birthDt(LocalDateTime value) { birthDt = value; return this; }
            public Builder sex(String value) { sex = value; return this; }
            public Builder street(String value) { street = value; return this; }
            public Builder city(String value) { city = value; return this; }
            public Builder cnty(String value) { cnty = value; return this; }
            public Builder state(String value) { state = value; return this; }
            public Builder zip(String value) { zip = value; return this; }
            public Builder zipsuf(String value) { zipsuf = value; return this; }
            public Builder phone(String value) { phone = value; return this; }
            public Builder recipNo(String value) { recipNo = value; return this; }
            public Builder maintFlag(String value) { maintFlag = value; return this; }
            public Builder ssn(String value) { ssn = value; return this; }
            public Builder insertDate(LocalDateTime value) { insertDate = value; return this; }
            public Builder fedeth(String value) { fedeth = value; return this; }
            public Builder race(String value) { race = value; return this; }
            public Builder extractDt(LocalDateTime value) { extractDt = value; return this; }

            public CareClientsDelta build() {
                return new CareClientsDelta(careId, careLastupDt, firstnm, lastnm, lastSuf, birthDt, sex, street, city,
                        cnty, state, zip, zipsuf, phone, recipNo, maintFlag, ssn, insertDate, fedeth, race, extractDt);
            }
        }
    }

    /// Provisional `@Id` `CARE_ID`: the table has no primary key, Spring Data JDBC needs one.
    /// Snapshot of every CARE client (`SN`): read for the moved and deleted cases of the delta. Not in the schema
    /// exports; created from `db/missing-objects.sql` with the columns of `STG_CRE_D_CARE_CLIENTS`.
    @Table("STG_CRE_SN_CARE_CLIENTS")
    public record CareClients(@Id String careId, LocalDateTime careLastupDt, String firstnm, String lastnm,
            String lastSuf, LocalDateTime birthDt, String sex, String street, String city, String cnty, String state,
            String zip, String zipsuf, String phone, String recipNo, String maintFlag, String ssn,
            LocalDateTime insertDate, String fedeth, String race, LocalDateTime extractDt) {

        /// `CareClients.builder().careId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String careId;
            private LocalDateTime careLastupDt;
            private String firstnm;
            private String lastnm;
            private String lastSuf;
            private LocalDateTime birthDt;
            private String sex;
            private String street;
            private String city;
            private String cnty;
            private String state;
            private String zip;
            private String zipsuf;
            private String phone;
            private String recipNo;
            private String maintFlag;
            private String ssn;
            private LocalDateTime insertDate;
            private String fedeth;
            private String race;
            private LocalDateTime extractDt;

            private Builder() {}

            public Builder careId(String value) { careId = value; return this; }
            public Builder careLastupDt(LocalDateTime value) { careLastupDt = value; return this; }
            public Builder firstnm(String value) { firstnm = value; return this; }
            public Builder lastnm(String value) { lastnm = value; return this; }
            public Builder lastSuf(String value) { lastSuf = value; return this; }
            public Builder birthDt(LocalDateTime value) { birthDt = value; return this; }
            public Builder sex(String value) { sex = value; return this; }
            public Builder street(String value) { street = value; return this; }
            public Builder city(String value) { city = value; return this; }
            public Builder cnty(String value) { cnty = value; return this; }
            public Builder state(String value) { state = value; return this; }
            public Builder zip(String value) { zip = value; return this; }
            public Builder zipsuf(String value) { zipsuf = value; return this; }
            public Builder phone(String value) { phone = value; return this; }
            public Builder recipNo(String value) { recipNo = value; return this; }
            public Builder maintFlag(String value) { maintFlag = value; return this; }
            public Builder ssn(String value) { ssn = value; return this; }
            public Builder insertDate(LocalDateTime value) { insertDate = value; return this; }
            public Builder fedeth(String value) { fedeth = value; return this; }
            public Builder race(String value) { race = value; return this; }
            public Builder extractDt(LocalDateTime value) { extractDt = value; return this; }

            public CareClients build() {
                return new CareClients(careId, careLastupDt, firstnm, lastnm, lastSuf, birthDt, sex, street, city, cnty,
                        state, zip, zipsuf, phone, recipNo, maintFlag, ssn, insertDate, fedeth, race, extractDt);
            }
        }
    }

    /// Provisional `@Id` `SOURCE_ID`: the table has no primary key, Spring Data JDBC needs one.
    /// Case maintenance of the day: `REC` `CASEMOV` moves `SOURCE_ID` onto `TARGET_ID`, `CASEDEL` deletes it.
    @Table("STG_CRE_D_CARE_CASE_MAINT")
    public record CareCaseMaintDelta(LocalDateTime addDt, String addTm, String rec, String comp, String sourceCase,
            String targetCase, @Id String sourceId, String targetId, String sourceNsId, String targetNsId,
            LocalDateTime extractDt, LocalDateTime insertDate) {

        /// `CareCaseMaintDelta.builder().addDt(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private LocalDateTime addDt;
            private String addTm;
            private String rec;
            private String comp;
            private String sourceCase;
            private String targetCase;
            private String sourceId;
            private String targetId;
            private String sourceNsId;
            private String targetNsId;
            private LocalDateTime extractDt;
            private LocalDateTime insertDate;

            private Builder() {}

            public Builder addDt(LocalDateTime value) { addDt = value; return this; }
            public Builder addTm(String value) { addTm = value; return this; }
            public Builder rec(String value) { rec = value; return this; }
            public Builder comp(String value) { comp = value; return this; }
            public Builder sourceCase(String value) { sourceCase = value; return this; }
            public Builder targetCase(String value) { targetCase = value; return this; }
            public Builder sourceId(String value) { sourceId = value; return this; }
            public Builder targetId(String value) { targetId = value; return this; }
            public Builder sourceNsId(String value) { sourceNsId = value; return this; }
            public Builder targetNsId(String value) { targetNsId = value; return this; }
            public Builder extractDt(LocalDateTime value) { extractDt = value; return this; }
            public Builder insertDate(LocalDateTime value) { insertDate = value; return this; }

            public CareCaseMaintDelta build() {
                return new CareCaseMaintDelta(addDt, addTm, rec, comp, sourceCase, targetCase, sourceId, targetId,
                        sourceNsId, targetNsId, extractDt, insertDate);
            }
        }
    }

    /// Provisional `@Id` `RUN_DATE`: the table has no primary key, Spring Data JDBC needs one, and the run date is the
    /// only column that is never NULL (the records are NULL when a CARE id has no cross-reference in MDM).
    /// Case moves (`ROWID_OBJECT` of the source and target cross-references) that MDM has no merge history for yet.
    @Table("CRE_SRC_MRG")
    public record SourceMerge(String srcRowidObject, String tgtRowidObject, @Id LocalDateTime runDate) {}
}
