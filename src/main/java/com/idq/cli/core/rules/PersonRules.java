package com.idq.cli.core.rules;

import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.isNumber;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.reference.ExceptionInfo;
import java.time.LocalDateTime;
import java.util.Objects;
import java.util.stream.Stream;

/// Demographic validation mapplets. See `docs/mappings/000_mapplets.md`.
///
/// * [#birthDate] - `mplt_BirthDate_Validation`
/// * [#gender] - `mplt_Gender_Validation`
/// * [#codeValue] - `mplt_Race_Validation`, `mplt_Ethnicity_Validation`, `mplt_Language_Validation`
/// * [#raceIndicators] - `mplt_Race_Ind_Validation`
/// * [#suffix] - `rule_Suffix_Std`
public final class PersonRules {

    static final String[] MEMBER_SOURCES = {"P23", "C21", "P88", "MAX", "P84", "PMR", "TRS", "CRE", "ECI", "WIC",
            "FSS", "TTF"};
    static final String[] INDIVIDUAL = {"HCP", "Indv", "INDV", "I"};

    private PersonRules() {}

    public record Checked<T>(T value, ExceptionInfo exception) {
        public boolean invalid() {
            return exception.present();
        }
    }

    /// A birth date in the future is rejected (the mapplet returns `NULL` for it) with `Invalid_Birth_Date`.
    public static Checked<LocalDateTime> birthDate(LocalDateTime birthDate, String partyType, String srcSys,
            EtlContext ctx) {
        boolean future = in(srcSys, MEMBER_SOURCES) && in(partyType, INDIVIDUAL) && birthDate != null
                && birthDate.isAfter(ctx.runStart());
        return future ? new Checked<>(null, ctx.exception("Invalid_Birth_Date"))
                : new Checked<>(birthDate, ExceptionInfo.NONE);
    }

    /// Source gender `M`/`F` becomes MDM `1`/`2`; `B`, `U` and organisations become `NULL`. Missing, numeric or
    /// any other value raises `Invalid_Gender` for individuals of a member source.
    public static Checked<String> gender(String genderCode, String partyType, String srcSys, EtlContext ctx) {
        boolean individual = in(partyType, "I", "Indv", "INDV", "HCP");
        String mdm = individual && "M".equals(genderCode) ? "1" : individual && "F".equals(genderCode) ? "2" : null;
        boolean invalid = in(trim(srcSys), MEMBER_SOURCES) && in(partyType, INDIVIDUAL)
                && (genderCode == null || isNumber(genderCode) || !in(genderCode, "M", "F", "U", "B"));
        return new Checked<>(mdm, invalid ? ctx.exception("Invalid_Gender") : ExceptionInfo.NONE);
    }

    /// Translates a source code through `V_LOOKUP_CODE_VALUE`; an untranslatable (or missing) code raises
    /// `exceptionCode`.
    public static Checked<String> codeValue(String codeType, String srcSys, String sourceCode, String exceptionCode,
            EtlContext ctx) {
        var master = sourceCode == null ? null : ctx.reference().masterCode(codeType, srcSys, sourceCode).orElse(null);
        return new Checked<>(master, master == null ? ctx.exception(exceptionCode) : ExceptionInfo.NONE);
    }

    public record RaceIndicators(String mdmRaceCd, String srcRaceIndList, ExceptionInfo exception) {}

    /// Five yes/no race indicators: one set gives its own code (`001` white, `002` black, `003` native american,
    /// `004` asian, `005` pacific islander), two give `006`, more give `007`, none raises `Invalid_Race`.
    public static RaceIndicators raceIndicators(Integer white, Integer black, Integer asian, Integer pacific,
            Integer nativeAmerican, EtlContext ctx) {
        boolean anyNull = Stream.of(white, black, asian, pacific, nativeAmerican).anyMatch(Objects::isNull);
        Integer count = anyNull ? null : white + black + asian + pacific + nativeAmerican;
        String code = switch (count) {
            case null -> null;
            case 0 -> null;
            case 1 -> white == 1 ? "001" : black == 1 ? "002" : nativeAmerican == 1 ? "003" : asian == 1 ? "004"
                    : pacific == 1 ? "005" : null;
            case 2 -> "006";
            default -> count > 2 ? "007" : null;
        };
        var list = Infa.concat("WH", white, "AA", black, "AS", asian, "PI", pacific, "NA", nativeAmerican);
        var exception = count == null || count == 0 ? ctx.exception("Invalid_Race") : ExceptionInfo.NONE;
        return new RaceIndicators(code, list, exception);
    }

    /// `rule_Suffix_Std`: suffix translated through `V_LOOKUP_CODE_VALUE` (no code-type filter in the rule);
    /// a non-blank untranslatable suffix raises `Invalid_Suffix`.
    public static Checked<String> suffix(String suffix, String srcSys, EtlContext ctx) {
        var std = suffix == null ? null : ctx.reference().masterCode(null, srcSys, suffix).orElse(null);
        boolean invalid = Infa.hasText(suffix) && std == null;
        return new Checked<>(std, invalid ? ctx.exception("Invalid_Suffix") : ExceptionInfo.NONE);
    }

    /// `mplt_Date_Greater_Than_Fifty_Years`: a date more than fifty years after the run becomes `NULL`.
    public static LocalDateTime notBeyondFiftyYears(LocalDateTime date, EtlContext ctx) {
        return date != null && date.isAfter(ctx.runStart().plusYears(50)) ? null : date;
    }
}
