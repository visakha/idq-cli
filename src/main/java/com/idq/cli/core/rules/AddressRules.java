package com.idq.cli.core.rules;

import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.isMissing;
import static com.idq.cli.core.Infa.substr;

import java.util.regex.Pattern;

/// Address expressions shared by every address mapping. See `docs/mappings/000_mapplets.md#address-validation`.
///
/// * [#stripSuite] - `exp_Prepare_For_Address_Validation`
/// * [#preScrub] - `rule_Addr_Line_Pre_Scrub1`
/// * [#postScrub] - `rule_Addr_Line_Post_Scrub`
/// * [#score] - `exp_Score_and_Exception_details`
/// * [#holdLines] - `exp_Address_Hold`
public final class AddressRules {

    private static final String LINE1_JUNK = "$)(@^!~*%+_={}[]|:;\"'<>?&";
    private static final String LINE2_JUNK = "$)(@^!~*%+-={}[]|:;\"'<>?&";
    private static final Pattern TRAILING_UNIT = Pattern.compile(
            "(?i)\\s+(#|Apt|Bldg|Dept|Fl|Hngr|Key|Lot|Pier|Rm|Slip|Spc|Stop|Ste|Trlr|Unit)$");

    private AddressRules() {}

    /// A trailing `STE #`, `SUITE`, `STE.` or `STE` without a number is cut before validation.
    public static String stripSuite(String line) {
        if (line == null) {
            return null;
        }
        var trimmed = line.strip();
        var up = trimmed.toUpperCase();
        for (var suffix : new String[] {"STE #", "SUITE", "STE.", "STE"}) {
            if (up.endsWith(suffix)) {
                return trimmed.substring(0, up.lastIndexOf(suffix));
            }
        }
        return line;
    }

    /// Upper case, remove junk characters, collapse `##` runs to `#` and turn back slashes into slashes.
    public static String preScrub(String line, boolean secondLine) {
        if (line == null) {
            return null;
        }
        var junk = secondLine ? LINE2_JUNK : LINE1_JUNK;
        var kept = line.toUpperCase().chars().filter(c -> junk.indexOf(c) < 0)
                .collect(StringBuilder::new, StringBuilder::appendCodePoint, StringBuilder::append).toString();
        return kept.strip().replaceAll(" {2,}", " ").replaceAll("#{2,}", "#").replace('\\', '/');
    }

    /// `C/O` becomes `c/o` and a dangling unit designator at the end of the line is dropped.
    public static String postScrub(String line) {
        if (line == null) {
            return null;
        }
        var s = line.strip().replaceAll(" {2,}", " ");
        if (s.startsWith("C/O ")) {
            s = "c/o " + s.substring(4);
        }
        s = s.replace(" C/O ", " c/o ");
        return TRAILING_UNIT.matcher(s).replaceAll("").strip();
    }

    /// Texas FIPS `48` default for Texas zip ranges when neither AddressDoctor nor the source supplies a state.
    public static String stateFips(String addressDoctorState, String sourceStateFips, String zip5) {
        if (!isMissing(addressDoctorState)) {
            return addressDoctorState;
        }
        if (!isMissing(sourceStateFips)) {
            return sourceStateFips;
        }
        boolean texasZip = zip5 != null && (zip5.equals("73301")
                || (zip5.compareTo("75001") >= 0 && zip5.compareTo("79999") <= 0 && !zip5.equals("75502"))
                || (zip5.compareTo("88510") >= 0 && zip5.compareTo("88589") <= 0));
        return texasZip ? "48" : null;
    }

    /// County FIPS kept for Texas, `999` when unknown, `996` out of state.
    public static String countyFips(String addressDoctorState, String addressDoctorCounty) {
        if ("48".equals(addressDoctorState)) {
            return addressDoctorCounty;
        }
        return addressDoctorCounty == null ? "999" : "996";
    }

    public enum Score { GOOD, EXCEPTION }

    /// Non physical-mail addresses with a mailability score up to 3, physical-mail (`002`) addresses scoring below 3
    /// with a match code starting `I` or `N`, and addresses whose type does not translate go to the exception
    /// queue. A missing score compares as `NULL` and therefore passes.
    public static Score score(String addressTypeMaster, String mailabilityScore, String matchCode) {
        if (mailabilityScore != null && addressTypeMaster != null) {
            if (!addressTypeMaster.equals("002") && mailabilityScore.compareTo("3") <= 0) {
                return Score.EXCEPTION;
            }
            if (addressTypeMaster.equals("002") && mailabilityScore.compareTo("3") < 0
                    && in(substr(matchCode, 1, 1), "I", "N")) {
                return Score.EXCEPTION;
            }
        }
        return addressTypeMaster == null ? Score.EXCEPTION : Score.GOOD;
    }

    /// Source address text written to the exception queue.
    public static String describe(String line1, String line2, String city, String state, String zip, String zipExt,
            String country) {
        return concat(line1, " ", line2, " ", city, " ", state, " ", zip, " ", zipExt, " ", country);
    }

    public record Lines(String line1, String line2) {}

    /// An empty first line is replaced by the second, which is then cleared when it repeats the first.
    public static Lines holdLines(String line1, String line2) {
        var first = isMissing(line1) ? line2 : line1;
        return new Lines(first, first != null && first.equals(line2) ? null : line2);
    }
}
