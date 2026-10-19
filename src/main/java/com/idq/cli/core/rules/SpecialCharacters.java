package com.idq.cli.core.rules;

/// The `STD_remove_special_char` token standardiser removes the entries of the IDQ reference table
/// `ref_special_char_list` (shared content, not part of the exports). Every character that is neither a letter nor a
/// digit is treated as listed; multiple spaces are collapsed and the value trimmed.
public final class SpecialCharacters {

    private SpecialCharacters() {}

    public static String remove(String value) {
        if (value == null) {
            return null;
        }
        var cleaned = value.replaceAll("[^\\p{L}\\p{Nd} ]", "").strip().replaceAll(" {2,}", " ");
        return cleaned.isEmpty() ? null : cleaned;
    }
}
