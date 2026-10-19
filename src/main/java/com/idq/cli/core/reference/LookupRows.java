package com.idq.cli.core.reference;

import java.util.Collection;
import java.util.Map;
import java.util.stream.Collectors;

/// Two-column lookup result rows (`LOOKUP_KEY`, `LOOKUP_VALUE`) returned by the source named queries.
public final class LookupRows {

    private LookupRows() {}

    public record KeyValue(String lookupKey, String lookupValue) {}

    public record KeyNumber(String lookupKey, Integer lookupValue) {}

    /// IDQ "return any" lookup cache: the first row per key wins.
    public static Map<String, String> toMap(Collection<KeyValue> rows) {
        return rows.stream().collect(Collectors.toMap(KeyValue::lookupKey, r -> String.valueOf(r.lookupValue()),
                (a, b) -> a));
    }

    public static Map<String, Integer> toNumberMap(Collection<KeyNumber> rows) {
        return rows.stream().filter(r -> r.lookupValue() != null)
                .collect(Collectors.toMap(KeyNumber::lookupKey, KeyNumber::lookupValue, (a, b) -> a));
    }
}
