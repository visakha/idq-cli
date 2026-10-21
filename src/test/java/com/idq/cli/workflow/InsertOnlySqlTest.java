package com.idq.cli.workflow;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/// The stored-procedure ports may run against production, so their SQL only inserts: no `DELETE`, `TRUNCATE` or `DROP`
/// outside comments and string literals (CLAUDE.md, insert-only rule).
class InsertOnlySqlTest {

    private static final Pattern FORBIDDEN = Pattern.compile("\\b(DELETE|TRUNCATE|DROP)\\b", Pattern.CASE_INSENSITIVE);

    @ParameterizedTest
    @ValueSource(strings = {"idq-to-oracle", "idq-to-snowflake"})
    void noDeleteTruncateOrDrop(String folder) throws IOException {
        List<Path> files;
        try (Stream<Path> walk = Files.walk(Path.of(folder))) {
            files = walk.filter(p -> p.toString().endsWith(".sql")).toList();
        }
        assertThat(files).isNotEmpty();
        assertThat(files).allSatisfy(file -> assertThat(FORBIDDEN.matcher(code(file)).find())
                .as("DELETE / TRUNCATE / DROP in %s", file).isFalse());
    }

    /// The file without `--` and `/* */` comments and with every string literal emptied.
    static String code(Path file) {
        String text;
        try {
            text = Files.readString(file);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        var out = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '\'') {
                int j = i + 1;
                while (j < text.length() && !(text.charAt(j) == '\''
                        && (j + 1 >= text.length() || text.charAt(j + 1) != '\''))) {
                    j += text.charAt(j) == '\'' ? 2 : 1;
                }
                out.append("''");
                i = j;
            } else if (text.startsWith("--", i)) {
                int end = text.indexOf('\n', i);
                i = end < 0 ? text.length() : end - 1;
            } else if (text.startsWith("/*", i)) {
                int end = text.indexOf("*/", i);
                i = end < 0 ? text.length() : end + 1;
            } else {
                out.append(c);
            }
        }
        return out.toString();
    }
}
