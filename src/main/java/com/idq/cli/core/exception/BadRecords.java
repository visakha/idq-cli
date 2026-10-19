package com.idq.cli.core.exception;

import com.idq.cli.core.Infa;
import com.idq.cli.core.reference.ExceptionInfo;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/// Fluent builder for [BadRecord], mirroring the exception expressions of the mappings:
///
/// ```java
/// BadRecords.of("TRS", ctx).exception(ExceptionInfo.of("Invalid_Plan", ref))
///         .attribute("Plan", planCode).ids(indvId, startDate, null).build();
/// ```
public final class BadRecords {

    private final String srcSys;
    private final String mappingName;
    private final LocalDateTime runDate;
    private String id1, id2, id3, type, code, desc, prefix, first, middle, last, suffix, aliasSuffix, gender;
    private String addressType, line1, line2, city, county, state, zip, zipExt, country, drCode, drDesc;
    private String primaryPhone, workPhone, secondaryPhone, email, attributeName, attributeValue;
    private BigDecimal drScore;
    private LocalDateTime birthDate, periodStart, periodEnd, deathDt;

    private BadRecords(String srcSys, String mappingName, LocalDateTime runDate) {
        this.srcSys = srcSys;
        this.mappingName = mappingName;
        this.runDate = runDate;
    }

    public static BadRecords of(String srcSys, String mappingName, LocalDateTime runDate) {
        return new BadRecords(srcSys, mappingName, runDate);
    }

    public BadRecords ids(Object srcSysId1, Object srcSysId2, Object srcSysId3) {
        id1 = Infa.toChar(srcSysId1);
        id2 = Infa.toChar(srcSysId2);
        id3 = Infa.toChar(srcSysId3);
        return this;
    }

    public BadRecords exception(ExceptionInfo info) {
        code = info.code();
        desc = info.description();
        type = info.type();
        return this;
    }

    public BadRecords exceptionType(String exceptionType) {
        type = exceptionType;
        return this;
    }

    public BadRecords attribute(String name, Object value) {
        attributeName = name;
        attributeValue = Infa.toChar(value);
        return this;
    }

    public BadRecords name(String prefixName, String firstName, String middleName, String lastName,
            String suffixName) {
        prefix = prefixName;
        first = firstName;
        middle = middleName;
        last = lastName;
        suffix = suffixName;
        return this;
    }

    public BadRecords aliasSuffix(String value) {
        aliasSuffix = value;
        return this;
    }

    public BadRecords person(LocalDateTime birth, String genderCode, LocalDateTime death) {
        birthDate = birth;
        gender = genderCode;
        deathDt = death;
        return this;
    }

    public BadRecords address(String type, String l1, String l2, String c, String cty, String st, String z,
            String zx, String cntry) {
        addressType = type;
        line1 = l1;
        line2 = l2;
        city = c;
        county = cty;
        state = st;
        zip = z;
        zipExt = zx;
        country = cntry;
        return this;
    }

    public BadRecords addressDoctor(String errorCode, String errorDesc, String mailabilityScore) {
        drCode = errorCode;
        drDesc = errorDesc;
        drScore = Infa.isNumber(mailabilityScore) ? new BigDecimal(mailabilityScore.strip()) : null;
        return this;
    }

    public BadRecords phones(String primary, String work, String secondary) {
        primaryPhone = primary;
        workPhone = work;
        secondaryPhone = secondary;
        return this;
    }

    public BadRecords email(String value) {
        email = value;
        return this;
    }

    public BadRecords period(LocalDateTime start, LocalDateTime end) {
        periodStart = start;
        periodEnd = end;
        return this;
    }

    public BadRecord build() {
        return new BadRecord(srcSys, id1, id2, id3, type, code, desc, runDate, prefix, first, middle, last, suffix,
                aliasSuffix, birthDate, gender, addressType, line1, line2, city, county, state, zip, zipExt, country,
                drCode, drDesc, drScore, primaryPhone, workPhone, secondaryPhone, email, attributeName,
                attributeValue, mappingName, periodStart, periodEnd, deathDt);
    }
}
