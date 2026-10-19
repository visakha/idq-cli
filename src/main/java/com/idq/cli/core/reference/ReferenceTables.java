package com.idq.cli.core.reference;

import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities of the shared lookup tables, column for column. The mappings read them through
/// [ReferenceQueries]; the mock-data seed writes them. The tables have no primary key; the `@Id`s are provisional.
public final class ReferenceTables {

    private ReferenceTables() {}

    /// Provisional `@Id` `SRC_CODE_VALUE`: the table has no primary key, Spring Data JDBC needs one.
    @Table("LOOKUP_CODE_VALUE")
    public record CodeValue(String createdBy, LocalDateTime createDate, String updatedBy, LocalDateTime lastUpdateDate,
            String codeType, String mstrRefCode, String mstrRefLabel, String mstrRefDesc, @Id String srcCodeValue,
            String srcSys, String srcCodeDesc) {}

    /// Provisional `@Id` `SRC_CODE_VALUE`: the table has no primary key, Spring Data JDBC needs one.
    @Table("V_LOOKUP_CODE_VALUE")
    public record MasterCodeValue(String mstrCodeValue, @Id String srcCodeValue, String srcSys, String codeType) {}

    /// Provisional `@Id` `EXC_LOOKUP_CODE_VALUE_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("EXC_LOOKUP_CODE_VALUE")
    public record ExceptionCode(@Id Long excLookupCodeValueId, String createdBy, LocalDateTime createDate,
            String updatedBy, LocalDateTime lastUpdateDate, String exceptionCode, String exceptionDesc,
            String exceptionType) {}

    /// Provisional `@Id` `NPA_ID`: the table has no primary key, Spring Data JDBC needs one.
    @Table("REF_PHN_AREA_CD")
    public record AreaCode(@Id String npaId, String typeOfCode, String assignable, String explanation, String reserved,
            String assigned, LocalDateTime assignmentDt, String use, String location, String country, String inService,
            LocalDateTime inServiceDt, String status, String planningLetters, String notes, String overlay,
            String overlayComplex, String parentNpaId, String service, String timeZone, String areaServed, String map,
            String inJeopardy, String reliefPlanningInProgress, String homeNpaLocalCalls, String homeNpaTollCalls,
            String foreignNpaLocalCalls, String foreignNpaTollCalls, String permHnpaLocalCalls,
            String permHnpaTollCalls, String permHnpaForeignLocalCalls, String dialingPlanNotes) {}

    /// Provisional `@Id` `NAME`: the table has no primary key, Spring Data JDBC needs one.
    @Table("REF_JUNK_NAME_LIST")
    public record JunkName(@Id String name, String nameGroup, String editLimitation, LocalDateTime addDt,
            String notes) {}
}
