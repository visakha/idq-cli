package com.idq.cli.core;

import static com.idq.cli.core.EtlPatterns.badData4BirthDate;
import static com.idq.cli.core.EtlPatterns.badData4Code;
import static com.idq.cli.core.EtlPatterns.badData4Gender;

import com.idq.cli.core.EtlPatterns.PersonName;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.core.rules.PersonRules;
import com.idq.cli.core.rules.PersonRules.Checked;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/// The demographic flow shared by `m_Tgt_C_S_<ECI|FSS|TTF|WIC>_Pty`: name standardization, birth date, gender,
/// ethnicity, language, race and suffix rules, then `Rtr_Exception` (every party is loaded; each failed rule also
/// writes an exception row).
///
/// [Spec] captures what differs per source: race by indicators or by code, whether language / suffix rules run, and
/// which exceptions apply only to rows from the main source table (child or client).
public final class PartyPattern {

    private PartyPattern() {}

    public enum Check { GENDER, ETHNICITY, RACE, LANGUAGE }

    public enum RaceSource { INDICATORS, CODE }

    public record Spec(String srcSys, RaceSource race, boolean language, boolean suffix,
            Set<Check> mainTableOnly) {}

    /// @param exceptionId2  `SRC_SYS_ID_2` of exception rows (source id)
    /// @param mainTable     the row comes from the source table that `mainTableOnly` checks apply to
    public record Input(String pkey, Object exceptionId2, boolean mainTable, String first, String middle,
            String last, String suffix, LocalDateTime birthDate, String gender, String ethnicity, String language,
            String raceCode, Integer white, Integer black, Integer asian, Integer pacific, Integer nativeAmerican,
            LocalDateTime periodStart) {}

    public record Result(Input in, NameStandardization.Output name, Checked<LocalDateTime> birth,
            Checked<String> gender, Checked<String> ethnicity, Checked<String> language, String mdmRaceCd,
            String srcRaceCd, Checked<String> suffix, List<BadRecord> exceptions) {}

    public static Result apply(Spec spec, Input in, EtlContext ctx) {
        var src = spec.srcSys();
        var name = NameStandardization.standardize(new NameStandardization.Input(in.first(), in.middle(), in.last(),
                Infa.fullName(in.first(), in.middle(), in.last()), null, in.suffix(), src), ctx);
        var birth = PersonRules.birthDate(in.birthDate(), "Indv", src, ctx);
        var gender = PersonRules.gender(in.gender(), "Indv", src, ctx);
        var ethnicity = PersonRules.codeValue("ETHNICITY", src, in.ethnicity(), "Invalid_Ethnicity", ctx);
        var language = spec.language() ? PersonRules.codeValue("LANGUAGE_CD", src, in.language(), "Invalid_Language",
                ctx) : new Checked<String>(null, ExceptionInfo.NONE);
        var suffix = spec.suffix() ? PersonRules.suffix(in.suffix(), src, ctx)
                : new Checked<String>(null, ExceptionInfo.NONE);
        String raceCd;
        String srcRaceCd;
        ExceptionInfo raceException;
        if (spec.race() == RaceSource.INDICATORS) {
            var race = PersonRules.raceIndicators(in.white(), in.black(), in.asian(), in.pacific(),
                    in.nativeAmerican(), ctx);
            raceCd = race.mdmRaceCd();
            srcRaceCd = race.srcRaceIndList();
            raceException = race.exception();
        } else {
            var race = PersonRules.codeValue("RACE", src, in.raceCode(), "Invalid_Race", ctx);
            raceCd = race.value();
            srcRaceCd = null;
            raceException = race.exception();
        }

        var person = new PersonName(name.prefix(), in.first(), in.middle(), in.last(), null);
        var bad = new ArrayList<BadRecord>();
        if (birth.invalid()) {
            bad.add(badData4BirthDate(ctx, in.pkey(), in.exceptionId2(), person, in.birthDate(), in.gender(),
                    birth.exception()));
        }
        if (applies(spec, Check.GENDER, in) && gender.exception().configured()) {
            bad.add(badData4Gender(ctx, in.pkey(), in.exceptionId2(), person, in.birthDate(), in.gender(),
                    gender.exception()));
        }
        if (applies(spec, Check.ETHNICITY, in) && ethnicity.exception().configured()) {
            bad.add(code(ctx, "Ethnicity_Cd", in.ethnicity(), in, name, ethnicity.exception()));
        }
        if (applies(spec, Check.RACE, in) && raceException.configured()) {
            bad.add(code(ctx, "Race_Cd", srcRaceCd == null ? in.raceCode() : srcRaceCd, in, name, raceException));
        }
        if (applies(spec, Check.LANGUAGE, in) && language.exception().configured()) {
            bad.add(code(ctx, "Language_Cd", in.language(), in, name, language.exception()));
        }
        if (suffix.invalid()) {
            bad.add(ctx.badRecord().ids(in.pkey(), in.exceptionId2(), null).exception(suffix.exception())
                    .attribute("Name Suffix", in.suffix()).name(null, in.first(), in.middle(), in.last(), in.suffix())
                    .aliasSuffix(suffix.value()).person(birth.value(), null, null).build());
        }
        return new Result(in, name, birth, gender, ethnicity, language, raceCd, srcRaceCd, suffix,
                bad.stream().filter(Objects::nonNull).toList());
    }

    private static boolean applies(Spec spec, Check check, Input in) {
        return !spec.mainTableOnly().contains(check) || in.mainTable();
    }

    private static BadRecord code(EtlContext ctx, String attribute, String value, Input in,
            NameStandardization.Output name, ExceptionInfo exception) {
        return badData4Code(ctx, attribute, value, in.pkey(), in.exceptionId2(),
                new PersonName(name.prefix(), name.first(), name.middle(), name.last(), null), in.birthDate(),
                in.gender(), in.periodStart(), exception);
    }
}
