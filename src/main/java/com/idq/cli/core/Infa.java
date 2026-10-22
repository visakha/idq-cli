package com.idq.cli.core;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.Objects;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/// Informatica transformation-language functions with their exact null semantics, so that ported expressions
/// read like the IDQ originals.
///
/// * `||` concatenation treats `NULL` as an empty string: [#concat].
/// * `LENGTH(RTRIM(x)) = 0` is `NULL` (therefore false) when `x` is `NULL`: [#isEmptyText].
/// * `LPAD` truncates values longer than the requested length: [#lpad].
public final class Infa {

    private static final Pattern NUMBER = Pattern.compile("\\s*[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?\\s*");

    private Infa() {}

    public static String concat(Object... parts) {
        return Arrays.stream(parts).map(Infa::text).collect(Collectors.joining());
    }

    /// `a || '|' || b || '|' || c`
    public static String pipe(Object... parts) {
        return Arrays.stream(parts).map(Infa::text).collect(Collectors.joining("|"));
    }

    public static String text(Object value) {
        return switch (value) {
            case null -> "";
            case BigDecimal decimal -> decimal.stripTrailingZeros().toPlainString();
            case Double d -> BigDecimal.valueOf(d).stripTrailingZeros().toPlainString();
            default -> value.toString();
        };
    }

    /// `TO_CHAR(n)`: `NULL` stays `NULL`.
    public static String toChar(Object value) {
        return value == null ? null : text(value);
    }

    public static String toChar(LocalDateTime value, String pattern) {
        return value == null ? null : value.format(DateTimeFormatter.ofPattern(pattern));
    }

    public static String trim(String value) {
        return value == null ? null : value.strip();
    }

    public static String rtrim(String value) {
        return value == null ? null : value.stripTrailing();
    }

    public static String ltrim(String value) {
        return value == null ? null : value.stripLeading();
    }

    public static String upper(String value) {
        return value == null ? null : value.toUpperCase();
    }

    public static String lower(String value) {
        return value == null ? null : value.toLowerCase();
    }

    /// `INITCAP(value)`: the first letter of every word in upper case, the others in lower case. Words are delimited by
    /// white space and by every character that is neither a letter nor a digit.
    public static String initcap(String value) {
        if (value == null) {
            return null;
        }
        var out = new StringBuilder(value.length());
        boolean wordStart = true;
        for (char c : value.toCharArray()) {
            out.append(wordStart ? Character.toUpperCase(c) : Character.toLowerCase(c));
            wordStart = !Character.isLetterOrDigit(c);
        }
        return out.toString();
    }

    /// `LENGTH(RTRIM(x)) = 0`, false for `NULL`.
    public static boolean isEmptyText(String value) {
        return value != null && value.isBlank();
    }

    /// `ISNULL(x) OR LENGTH(RTRIM(x)) = 0`
    public static boolean isMissing(String value) {
        return value == null || value.isBlank();
    }

    public static boolean hasText(String value) {
        return !isMissing(value);
    }

    /// `LPAD(value, length, pad)`, truncating on the right when the value is longer, as Informatica does.
    public static String lpad(Object value, int length, char pad) {
        if (value == null) {
            return null;
        }
        var s = text(value);
        return s.length() >= length ? s.substring(0, length) : String.valueOf(pad).repeat(length - s.length()) + s;
    }

    /// `SUBSTR(value, start, length)` with 1-based `start`; 0 is treated as 1 and negative counts from the end.
    public static String substr(String value, int start, int length) {
        if (value == null) {
            return null;
        }
        int from = start > 0 ? start - 1 : start == 0 ? 0 : Math.max(0, value.length() + start);
        if (from >= value.length() || length <= 0) {
            return "";
        }
        return value.substring(from, Math.min(value.length(), from + length));
    }

    public static String substr(String value, int start) {
        return value == null ? null : substr(value, start, value.length());
    }

    public static boolean isNumber(String value) {
        return value != null && NUMBER.matcher(value).matches();
    }

    @SafeVarargs
    public static <T> boolean in(T value, T... candidates) {
        return value != null && Arrays.asList(candidates).contains(value);
    }

    @SafeVarargs
    public static <T> T nvl(T... values) {
        return Arrays.stream(values).filter(Objects::nonNull).findFirst().orElse(null);
    }

    public static LocalDateTime greatest(LocalDateTime a, LocalDateTime b) {
        if (a == null || b == null) {
            return a == null ? b : a;
        }
        return a.isAfter(b) ? a : b;
    }

    /// Full name exactly as the mappings build it:
    /// `LTRIM(RTRIM(FIRST || IIF(NOT ISNULL(MID), ' ' || LTRIM(RTRIM(MID)), '') || ' ' || LTRIM(LAST)))`.
    public static String fullName(String first, String middle, String last) {
        return trim(concat(first, middle == null ? "" : " " + trim(middle), " ", ltrim(last)));
    }
}
