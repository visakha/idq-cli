package com.idq.cli.core.rules;

import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.hasText;
import static com.idq.cli.core.Infa.ltrim;
import static com.idq.cli.core.Infa.trim;
import static com.idq.cli.core.Infa.upper;

import com.idq.cli.core.EtlContext;
import java.util.Arrays;
import java.util.stream.Collectors;

/// `mplt_Name_Standardization_Indv_Member` and its nested `mplt_Name_Standardization_Trailing_Num_Removal`.
/// See `docs/mappings/000_mapplets.md#name-standardization`.
///
/// 1. prefix and suffix are translated through `V_LOOKUP_CODE_VALUE` (`PREFIX`, `SUFFIX`); a non-blank value that
///    does not translate gets `Invalid_Prefix` / `Invalid_Suffix`,
/// 2. first and last names found in `REF_JUNK_NAME_LIST` are blanked,
/// 3. junk characters are removed per field and multiple spaces collapsed,
/// 4. names are title cased,
/// 5. a zero between letters becomes the letter `o`, and anything from the first digit onwards is cut,
/// 6. the full name is rebuilt from the cleaned parts.
public final class NameStandardization {

    private static final String FIRST_JUNK = "~!`@#$%^&*()_+=\":;?/.>,<\t";
    private static final String MIDDLE_JUNK = "~`!@#$%^&*()_-+=}{[]|\\\"':;?/>.<,\t";
    private static final String LAST_JUNK = "~`!@#$%^&*()_+=|\\}{[]\";:?>.<,\t";
    private static final String FULL_JUNK = "~`!@#$%^*()_+=\\|}]{[\":;?/>.<,\t";

    private NameStandardization() {}

    public record Input(String first, String middle, String last, String full, String prefix, String suffix,
            String srcSys) {}

    public record Output(String first, String middle, String last, String full, String srcFull, String prefix,
            String suffix, String prefixExceptionCode, String suffixExceptionCode) {}

    public static Output standardize(Input in, EtlContext ctx) {
        var ref = ctx.reference();
        var stdPrefix = in.prefix() == null ? null : ref.masterCode("PREFIX", in.srcSys(), in.prefix()).orElse(null);
        var stdSuffix = in.suffix() == null ? null : ref.masterCode("SUFFIX", in.srcSys(), in.suffix()).orElse(null);
        var srcFull = in.full() == null ? concat(trim(in.first()), " ", trim(in.last())) : in.full();

        var first = ref.isJunkFirstName(trim(upper(in.first()))) ? null : in.first();
        var last = ref.isJunkLastName(trim(upper(in.last()))) ? null : in.last();
        var trailing = removeTrailingNumbers(
                titleCase(removeJunk(first, FIRST_JUNK)),
                titleCase(removeJunk(in.middle(), MIDDLE_JUNK)),
                titleCase(removeJunk(last, LAST_JUNK)),
                titleCase(removeJunk(srcFull, FULL_JUNK)));
        return new Output(trailing.first(), trailing.middle(), trailing.last(), trailing.full(), srcFull, stdPrefix,
                stdSuffix,
                hasText(in.prefix()) && stdPrefix == null ? "Invalid_Prefix" : null,
                hasText(in.suffix()) && stdSuffix == null ? "Invalid_Suffix" : null);
    }

    public record Parts(String first, String middle, String last, String full) {}

    /// `mplt_Name_Standardization_Trailing_Num_Removal`, also called directly by `m_Tgt_C_S_TRS_Pty_Nm`.
    ///
    /// The IDQ middle-name expression returns the *last* name in its "keep" branch; that behaviour is preserved.
    public static Parts removeTrailingNumbers(String first, String middle, String last, String full) {
        var f = cutAtDigit(zeroToO(first), zeroToO(first));
        var l = cutAtDigit(zeroToO(last), zeroToO(last));
        var m = cutAtDigit(zeroToO(middle), zeroToO(last));
        var rebuilt = trim(concat(f, hasText(m) ? " " + trim(m) : "", " ", ltrim(l)));
        return new Parts(f, m, l, rebuilt);
    }

    static String zeroToO(String name) {
        if (name == null) {
            return null;
        }
        var label = label(name);
        var trimmed = name.strip();
        boolean endsWithDigit = !trimmed.isEmpty() && Character.isDigit(trimmed.charAt(trimmed.length() - 1));
        return label.contains("X0X") && !endsWithDigit ? name.replace('0', 'o') : name;
    }

    /// `keepWhenZeroEnding` is what the IDQ expression returns when the name ends in `0` and the label does not
    /// end in two digits.
    static String cutAtDigit(String name, String keepWhenZeroEnding) {
        if (name == null) {
            return null;
        }
        var label = label(name).strip();
        var trimmed = name.strip();
        boolean lastTwoDigits = label.length() >= 3 && label.substring(label.length() - 3, label.length() - 1)
                .equals("99");
        String result;
        if (!lastTwoDigits && trimmed.endsWith("0")) {
            result = keepWhenZeroEnding;
        } else if (label.indexOf('9') >= 0 || label.indexOf('0') >= 0) {
            int firstDigit = firstDigit(name);
            result = name.substring(0, firstDigit);
        } else {
            result = name;
        }
        return trim(result);
    }

    private static int firstDigit(String name) {
        for (int i = 0; i < name.length(); i++) {
            if (Character.isDigit(name.charAt(i))) {
                return i;
            }
        }
        return name.length();
    }

    /// Character labels as produced by the IDQ labelers: letters `X`, zero `0`, other digits `9`.
    static String label(String name) {
        return name.chars().mapToObj(c -> Character.isLetter(c) ? "X" : c == '0' ? "0" : Character.isDigit(c) ? "9"
                : String.valueOf((char) c)).collect(Collectors.joining());
    }

    static String removeJunk(String value, String junk) {
        if (value == null) {
            return null;
        }
        var kept = value.chars().filter(c -> junk.indexOf(c) < 0)
                .collect(StringBuilder::new, StringBuilder::appendCodePoint, StringBuilder::append).toString();
        return kept.strip().replaceAll(" {2,}", " ");
    }

    static String titleCase(String value) {
        if (value == null) {
            return null;
        }
        return Arrays.stream(value.split(" ", -1))
                .map(word -> word.isEmpty() ? word
                        : word.substring(0, 1).toUpperCase() + word.substring(1).toLowerCase())
                .collect(Collectors.joining(" "));
    }
}
