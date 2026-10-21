package com.idq.cli.core.reference;

import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the shared lookup tables, column for column. The mappings read them through
/// [ReferenceQueries]; the mock-data seed writes them. `LOOKUP_CODE_VALUE` has a composite primary key; the other
/// tables have none, so their `@Id`s are provisional.
public final class ReferenceTables {

    private ReferenceTables() {}

    /// Composite primary key [Key] `(CODE_TYPE, SRC_CODE_VALUE, SRC_SYS)`.
    @Table("LOOKUP_CODE_VALUE")
    public record CodeValue(@Id Key key, String createdBy, LocalDateTime createDate, String updatedBy,
            LocalDateTime lastUpdateDate, String mstrRefCode, String mstrRefLabel, String mstrRefDesc,
            String srcCodeDesc) {

        /// Primary key `(CODE_TYPE, SRC_CODE_VALUE, SRC_SYS)`.
        public record Key(String codeType, String srcCodeValue, String srcSys) {}

        /// `CodeValue.builder().key(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Key key;
            private String createdBy;
            private LocalDateTime createDate;
            private String updatedBy;
            private LocalDateTime lastUpdateDate;
            private String mstrRefCode;
            private String mstrRefLabel;
            private String mstrRefDesc;
            private String srcCodeDesc;

            private Builder() {}

            public Builder key(Key value) { key = value; return this; }
            public Builder createdBy(String value) { createdBy = value; return this; }
            public Builder createDate(LocalDateTime value) { createDate = value; return this; }
            public Builder updatedBy(String value) { updatedBy = value; return this; }
            public Builder lastUpdateDate(LocalDateTime value) { lastUpdateDate = value; return this; }
            public Builder mstrRefCode(String value) { mstrRefCode = value; return this; }
            public Builder mstrRefLabel(String value) { mstrRefLabel = value; return this; }
            public Builder mstrRefDesc(String value) { mstrRefDesc = value; return this; }
            public Builder srcCodeDesc(String value) { srcCodeDesc = value; return this; }

            public CodeValue build() {
                return new CodeValue(key, createdBy, createDate, updatedBy, lastUpdateDate, mstrRefCode, mstrRefLabel,
                        mstrRefDesc, srcCodeDesc);
            }
        }
    }

    /// Provisional `@Id` `SRC_CODE_VALUE`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_LOOKUP_CODE_VALUE")
    public record MasterCodeValue(String mstrCodeValue, @Id String srcCodeValue, String srcSys, String codeType) {

        /// `MasterCodeValue.builder().mstrCodeValue(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String mstrCodeValue;
            private String srcCodeValue;
            private String srcSys;
            private String codeType;

            private Builder() {}

            public Builder mstrCodeValue(String value) { mstrCodeValue = value; return this; }
            public Builder srcCodeValue(String value) { srcCodeValue = value; return this; }
            public Builder srcSys(String value) { srcSys = value; return this; }
            public Builder codeType(String value) { codeType = value; return this; }

            public MasterCodeValue build() {
                return new MasterCodeValue(mstrCodeValue, srcCodeValue, srcSys, codeType);
            }
        }
    }

    /// Provisional `@Id` `EXC_LOOKUP_CODE_VALUE_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("EXC_LOOKUP_CODE_VALUE")
    public record ExceptionCode(@Id Long excLookupCodeValueId, String createdBy, LocalDateTime createDate,
            String updatedBy, LocalDateTime lastUpdateDate, String exceptionCode, String exceptionDesc,
            String exceptionType) {

        /// `ExceptionCode.builder().excLookupCodeValueId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private Long excLookupCodeValueId;
            private String createdBy;
            private LocalDateTime createDate;
            private String updatedBy;
            private LocalDateTime lastUpdateDate;
            private String exceptionCode;
            private String exceptionDesc;
            private String exceptionType;

            private Builder() {}

            public Builder excLookupCodeValueId(Long value) { excLookupCodeValueId = value; return this; }
            public Builder createdBy(String value) { createdBy = value; return this; }
            public Builder createDate(LocalDateTime value) { createDate = value; return this; }
            public Builder updatedBy(String value) { updatedBy = value; return this; }
            public Builder lastUpdateDate(LocalDateTime value) { lastUpdateDate = value; return this; }
            public Builder exceptionCode(String value) { exceptionCode = value; return this; }
            public Builder exceptionDesc(String value) { exceptionDesc = value; return this; }
            public Builder exceptionType(String value) { exceptionType = value; return this; }

            public ExceptionCode build() {
                return new ExceptionCode(excLookupCodeValueId, createdBy, createDate, updatedBy, lastUpdateDate,
                        exceptionCode, exceptionDesc, exceptionType);
            }
        }
    }

    /// Provisional `@Id` `NPA_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("REF_PHN_AREA_CD")
    public record AreaCode(@Id String npaId, String typeOfCode, String assignable, String explanation, String reserved,
            String assigned, LocalDateTime assignmentDt, String use, String location, String country, String inService,
            LocalDateTime inServiceDt, String status, String planningLetters, String notes, String overlay,
            String overlayComplex, String parentNpaId, String service, String timeZone, String areaServed, String map,
            String inJeopardy, String reliefPlanningInProgress, String homeNpaLocalCalls, String homeNpaTollCalls,
            String foreignNpaLocalCalls, String foreignNpaTollCalls, String permHnpaLocalCalls,
            String permHnpaTollCalls, String permHnpaForeignLocalCalls, String dialingPlanNotes) {

        /// `AreaCode.builder().npaId(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String npaId;
            private String typeOfCode;
            private String assignable;
            private String explanation;
            private String reserved;
            private String assigned;
            private LocalDateTime assignmentDt;
            private String use;
            private String location;
            private String country;
            private String inService;
            private LocalDateTime inServiceDt;
            private String status;
            private String planningLetters;
            private String notes;
            private String overlay;
            private String overlayComplex;
            private String parentNpaId;
            private String service;
            private String timeZone;
            private String areaServed;
            private String map;
            private String inJeopardy;
            private String reliefPlanningInProgress;
            private String homeNpaLocalCalls;
            private String homeNpaTollCalls;
            private String foreignNpaLocalCalls;
            private String foreignNpaTollCalls;
            private String permHnpaLocalCalls;
            private String permHnpaTollCalls;
            private String permHnpaForeignLocalCalls;
            private String dialingPlanNotes;

            private Builder() {}

            public Builder npaId(String value) { npaId = value; return this; }
            public Builder typeOfCode(String value) { typeOfCode = value; return this; }
            public Builder assignable(String value) { assignable = value; return this; }
            public Builder explanation(String value) { explanation = value; return this; }
            public Builder reserved(String value) { reserved = value; return this; }
            public Builder assigned(String value) { assigned = value; return this; }
            public Builder assignmentDt(LocalDateTime value) { assignmentDt = value; return this; }
            public Builder use(String value) { use = value; return this; }
            public Builder location(String value) { location = value; return this; }
            public Builder country(String value) { country = value; return this; }
            public Builder inService(String value) { inService = value; return this; }
            public Builder inServiceDt(LocalDateTime value) { inServiceDt = value; return this; }
            public Builder status(String value) { status = value; return this; }
            public Builder planningLetters(String value) { planningLetters = value; return this; }
            public Builder notes(String value) { notes = value; return this; }
            public Builder overlay(String value) { overlay = value; return this; }
            public Builder overlayComplex(String value) { overlayComplex = value; return this; }
            public Builder parentNpaId(String value) { parentNpaId = value; return this; }
            public Builder service(String value) { service = value; return this; }
            public Builder timeZone(String value) { timeZone = value; return this; }
            public Builder areaServed(String value) { areaServed = value; return this; }
            public Builder map(String value) { map = value; return this; }
            public Builder inJeopardy(String value) { inJeopardy = value; return this; }
            public Builder reliefPlanningInProgress(String value) { reliefPlanningInProgress = value; return this; }
            public Builder homeNpaLocalCalls(String value) { homeNpaLocalCalls = value; return this; }
            public Builder homeNpaTollCalls(String value) { homeNpaTollCalls = value; return this; }
            public Builder foreignNpaLocalCalls(String value) { foreignNpaLocalCalls = value; return this; }
            public Builder foreignNpaTollCalls(String value) { foreignNpaTollCalls = value; return this; }
            public Builder permHnpaLocalCalls(String value) { permHnpaLocalCalls = value; return this; }
            public Builder permHnpaTollCalls(String value) { permHnpaTollCalls = value; return this; }
            public Builder permHnpaForeignLocalCalls(String value) { permHnpaForeignLocalCalls = value; return this; }
            public Builder dialingPlanNotes(String value) { dialingPlanNotes = value; return this; }

            public AreaCode build() {
                return new AreaCode(npaId, typeOfCode, assignable, explanation, reserved, assigned, assignmentDt, use,
                        location, country, inService, inServiceDt, status, planningLetters, notes, overlay,
                        overlayComplex, parentNpaId, service, timeZone, areaServed, map, inJeopardy,
                        reliefPlanningInProgress, homeNpaLocalCalls, homeNpaTollCalls, foreignNpaLocalCalls,
                        foreignNpaTollCalls, permHnpaLocalCalls, permHnpaTollCalls, permHnpaForeignLocalCalls,
                        dialingPlanNotes);
            }
        }
    }

    /// Provisional `@Id` `NAME`: the table has no primary key, Spring Data JDBC needs one.
    @Table("REF_JUNK_NAME_LIST")
    public record JunkName(@Id String name, String nameGroup, String editLimitation, LocalDateTime addDt,
            String notes) {

        /// `JunkName.builder().name(...).build()`; columns not set are `NULL`.
        public static Builder builder() {
            return new Builder();
        }

        public static final class Builder {
            private String name;
            private String nameGroup;
            private String editLimitation;
            private LocalDateTime addDt;
            private String notes;

            private Builder() {}

            public Builder name(String value) { name = value; return this; }
            public Builder nameGroup(String value) { nameGroup = value; return this; }
            public Builder editLimitation(String value) { editLimitation = value; return this; }
            public Builder addDt(LocalDateTime value) { addDt = value; return this; }
            public Builder notes(String value) { notes = value; return this; }

            public JunkName build() {
                return new JunkName(name, nameGroup, editLimitation, addDt, notes);
            }
        }
    }
}
