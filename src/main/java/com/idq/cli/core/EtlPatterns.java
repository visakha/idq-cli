package com.idq.cli.core;

import static com.idq.cli.core.Infa.isMissing;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.RowFactory;
import com.idq.cli.core.target.StagingRow;
import java.time.LocalDateTime;

/// ETL patterns that recur across the IDQ mappings, written once.
///
/// | pattern               | IDQ shape                                                                    |
/// |-----------------------|------------------------------------------------------------------------------|
/// | [#timeStampNow]       | `$sys.MappingRunStartTime` / `SYSTIMESTAMP()`                                |
/// | [#memberRole]         | `<party key> \|\| '\|Member'` party-role foreign key                          |
/// | [#badData4Name]       | `Missing_First_Name` / `Missing_Last_Name` exception row                     |
/// | [#badData4BirthDate]  | `Invalid_Birth_Date` exception row                                           |
/// | [#badData4DeathDate]  | `Invalid_Death_Date` exception row                                           |
/// | [#badData4Gender]     | `Invalid_Gender` exception row                                               |
/// | [#badData4Code]       | race / ethnicity / language / suffix exception rows                          |
/// | [#badData4Phone]      | phone exception row of the phone-and-e-mail mappings                         |
/// | [#badData4Email]      | e-mail exception row of the phone-and-e-mail mappings                        |
/// | [#write2TargetPhone]  | `C_S_*_PTY_RLE_PHN` row                                                      |
/// | [#write2TargetEmail]  | `C_S_*_PTY_RLE_EADDR` row (`ADDR_TP 001`, `Active`, valid)                   |
public final class EtlPatterns {

    public static final String MEMBER = "Member";

    private EtlPatterns() {}

    public static LocalDateTime timeStampNow(EtlContext ctx) {
        return ctx.runStart();
    }

    public static String memberRole(String partyKey) {
        return pipe(partyKey, MEMBER);
    }

    /// Which name part is missing, in the order the mappings test them (first name before last name).
    public static String missingNameCode(String first, String last) {
        return isMissing(first) ? "Missing_First_Name" : isMissing(last) ? "Missing_Last_Name" : null;
    }

    public static BadRecord badData4Name(EtlContext ctx, String srcSysId1, String first, String middle, String last,
            LocalDateTime birthDate, LocalDateTime periodStart, String attributeValue) {
        var code = missingNameCode(first, last);
        return ctx.badRecord().ids(srcSysId1, null, null).exception(ctx.exception(code))
                .attribute(isMissing(first) ? "First Name" : "Last Name", attributeValue)
                .name(null, first, middle, last, null).person(birthDate, null, null)
                .period(periodStart, null).build();
    }

    public static BadRecord badData4BirthDate(EtlContext ctx, String key, Object id2, PersonName name,
            LocalDateTime birthDate, String gender, ExceptionInfo exception) {
        return ctx.badRecord().ids(key, id2, null).exception(exception)
                .attribute("Birth Date", Infa.toChar(birthDate, "MM/dd/yyyy"))
                .name(name.prefix(), name.first(), name.middle(), name.last(), name.suffix())
                .person(birthDate, gender, null).build();
    }

    public static BadRecord badData4DeathDate(EtlContext ctx, String key, PersonName name, LocalDateTime birthDate,
            String gender, LocalDateTime deathDate, LocalDateTime periodStart, ExceptionInfo exception) {
        return ctx.badRecord().ids(key, null, null).exception(exception)
                .attribute("Death Date", Infa.toChar(deathDate))
                .name(name.prefix(), name.first(), name.middle(), name.last(), name.suffix())
                .person(birthDate, gender, deathDate).period(periodStart, null).build();
    }

    public static BadRecord badData4Gender(EtlContext ctx, String key, Object id2, PersonName name,
            LocalDateTime birthDate, String gender, ExceptionInfo exception) {
        return ctx.badRecord().ids(key, id2, null).exception(exception).attribute("Gender", gender)
                .name(name.prefix(), name.first(), name.middle(), name.last(), name.suffix())
                .person(birthDate, gender, null).build();
    }

    public static BadRecord badData4Code(EtlContext ctx, String attribute, String sourceValue, String key, Object id2,
            PersonName name, LocalDateTime birthDate, String gender, LocalDateTime periodStart,
            ExceptionInfo exception) {
        return ctx.badRecord().ids(key, id2, null).exception(exception).attribute(attribute, sourceValue)
                .name(name.prefix(), name.first(), name.middle(), name.last(), null)
                .person(birthDate, gender, null).period(periodStart, null).build();
    }

    /// Phone exception row: the attribute name follows the usage type (`001` main, `002` work, `003` other).
    public static BadRecord badData4Phone(EtlContext ctx, String srcSysId1, Object srcSysId2, Object srcSysId3,
            String phone, String usageType, String preference, LocalDateTime periodStart, ExceptionInfo exception,
            String exceptionType) {
        var attribute = switch (usageType == null ? "" : usageType) {
            case "001" -> "Main Phone";
            case "002" -> "Work Phone";
            case "003" -> "Other Phone";
            default -> null;
        };
        return ctx.badRecord().ids(srcSysId1, srcSysId2, srcSysId3).exception(exception)
                .exceptionType(exceptionType).attribute(attribute, phone)
                .phones("Primary".equals(preference) ? phone : null, "Work".equals(usageType) ? phone : null,
                        "Secondary".equals(preference) ? phone : null)
                .period(periodStart, null).build();
    }

    public static BadRecord badData4Email(EtlContext ctx, String srcSysId1, Object srcSysId2, String email,
            LocalDateTime periodStart, ExceptionInfo exception) {
        return ctx.badRecord().ids(srcSysId1, srcSysId2, null).exception(exception).attribute("Email", email)
                .email(email).period(periodStart, null).build();
    }

    public static <R extends StagingRow<Columns.Phone>> R write2TargetPhone(RowFactory<Columns.Phone, R> factory,
            String pkey, String partyRoleFk, String phoneType, String usageType, String phone, String preference,
            MdmAudit audit) {
        return factory.create(pkey, audit, new Columns.Phone(partyRoleFk, phoneType, usageType, phone, preference));
    }

    public static <R extends StagingRow<Columns.Email>> R write2TargetEmail(RowFactory<Columns.Email, R> factory,
            String pkey, String partyRoleFk, String email, MdmAudit audit) {
        return factory.create(pkey, audit, new Columns.Email(partyRoleFk, "001", null, email, "Active", "Y"));
    }

    /// Name parts as written to exception rows.
    public record PersonName(String prefix, String first, String middle, String last, String suffix) {
        public static PersonName of(String first, String middle, String last) {
            return new PersonName(null, trim(first), trim(middle), trim(last), null);
        }
    }
}
