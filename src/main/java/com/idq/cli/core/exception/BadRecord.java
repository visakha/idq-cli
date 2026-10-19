package com.idq.cli.core.exception;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

/// One row of `EXC_STG_BAD_REC_MEMB`, the data-quality exception queue shared by every member mapping.
/// Build it with [BadRecords].
///
/// The table has no key; `MAPPING_NAME` (never null) is marked as identifier only because Spring Data JDBC requires
/// one. Rows are only ever inserted.
@Table("EXC_STG_BAD_REC_MEMB")
public record BadRecord(
        String srcSys,
        @Column("SRC_SYS_ID_1") String srcSysId1,
        @Column("SRC_SYS_ID_2") String srcSysId2,
        @Column("SRC_SYS_ID_3") String srcSysId3,
        String exceptionType,
        String exceptionCode,
        String exceptionDesc,
        LocalDateTime runDate,
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
        @Id String mappingName,
        LocalDateTime periodStartDate,
        LocalDateTime periodEndDate,
        LocalDateTime deathDt) {}
