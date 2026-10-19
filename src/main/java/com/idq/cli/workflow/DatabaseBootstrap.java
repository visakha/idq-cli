package com.idq.cli.workflow;

import com.idq.cli.config.EtlSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

/// Creates the objects of `db/missing-objects.sql` that do not exist yet. Only `CREATE TABLE` statements are
/// accepted; anything else in the file is rejected, so this can never drop or alter a table.
@Component
public class DatabaseBootstrap {

    private static final Pattern CREATE = Pattern.compile("^CREATE TABLE \"([A-Z0-9_$]+)\"", Pattern.CASE_INSENSITIVE);

    private final NamedParameterJdbcTemplate jdbc;
    private final EtlSettings settings;

    public DatabaseBootstrap(NamedParameterJdbcTemplate jdbc, EtlSettings settings) {
        this.jdbc = jdbc;
        this.settings = settings;
    }

    /// @return names of the tables created
    public List<String> createMissingObjects() {
        if (!settings.bootstrapMissingObjects()) {
            return List.of();
        }
        var created = new ArrayList<String>();
        for (var statement : statements()) {
            var matcher = CREATE.matcher(statement);
            if (!matcher.find()) {
                throw new IllegalStateException("Only CREATE TABLE is allowed in missing-objects.sql: " + statement);
            }
            var table = matcher.group(1);
            var exists = jdbc.queryForObject("SELECT COUNT(*) FROM USER_TABLES WHERE TABLE_NAME = :t",
                    Map.of("t", table), Integer.class);
            if (exists != null && exists == 0) {
                jdbc.getJdbcTemplate().execute(statement);
                created.add(table);
            }
        }
        return created;
    }

    static List<String> statements() {
        try (var in = new ClassPathResource("db/missing-objects.sql").getInputStream()) {
            var text = new String(in.readAllBytes(), StandardCharsets.UTF_8).lines()
                    .filter(line -> !line.strip().startsWith("--")).reduce("", (a, b) -> a + "\n" + b);
            return java.util.Arrays.stream(text.split(";")).map(String::strip).filter(s -> !s.isEmpty()).toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
