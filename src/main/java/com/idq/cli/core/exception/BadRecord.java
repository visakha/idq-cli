package com.idq.cli.core.exception;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// One row of `EXC_STG_BAD_REC_MEMB`, the data-quality exception queue shared by every member mapping.
/// Build it with [BadRecords].
///
/// Identified by [Key], the table's composite unique key. It is a UNIQUE constraint rather than a primary key because
/// mappings leave the second and third source ids (and an uncatalogued exception's type) `NULL`, as IDQ does.
/// Rows are only ever inserted.
@Table("EXC_STG_BAD_REC_MEMB")
public record BadRecord(
        @Id Key key,
        String exceptionDesc,
        String prefix,
        String firstName,
        String middleName,
        String lastName,
        String suffix,
        String aliasSuffix,
        LocalDateTime birthDate,
        String gender,
        String addressType,
        @Column("ADDRESS_LINE_1") String addressLine1,
        @Column("ADDRESS_LINE_2") String addressLine2,
        String addressCity,
        String addressCounty,
        String addressState,
        String addressZip,
        String addressZipExt,
        String addressCountry,
        String addressDrErrorCode,
        String addressDrErrorDesc,
        BigDecimal addressDrMailabilityScore,
        String primaryPhone,
        String workPhone,
        String secondaryPhone,
        String email,
        String attributeName,
        String attributeValue,
        String mappingName,
        LocalDateTime periodStartDate,
        LocalDateTime periodEndDate,
        LocalDateTime deathDt) {

    /// Unique key `(SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, EXCEPTION_TYPE, EXCEPTION_CODE, RUN_DATE)`.
    public record Key(
            String srcSys,
            @Column("SRC_SYS_ID_1") String srcSysId1,
            @Column("SRC_SYS_ID_2") String srcSysId2,
            @Column("SRC_SYS_ID_3") String srcSysId3,
            String exceptionType,
            String exceptionCode,
            LocalDateTime runDate) {}
}
