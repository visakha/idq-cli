package com.idq.cli.workflow;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.SourceSystem;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/// Calls the Oracle stored procedures that replace the IDQ mappings (`etl_process=ORA_SP`).
///
/// The procedures and their order come from the workflow's run script,
/// `<idq.ora-sp.dir>/<workflow>/run_<workflow>.sql` (its `EXEC sp_ors_main_<mapping>` lines, in taskflow order). Each
/// procedure commits on success and rolls back and re-raises on error. With `mock_ora_sp=true` nothing is called; the `EXEC` that would run is reported instead.
@Component
public class OraSpRunner {

    static final String PREFIX = "sp_ors_main_";
    private static final Pattern EXEC = Pattern.compile("^EXEC\\s+(" + PREFIX + "\\w+)\\s*;?\\s*$",
            Pattern.CASE_INSENSITIVE);

    private final JdbcTemplate jdbc;
    private final EtlSettings settings;

    public OraSpRunner(JdbcTemplate jdbc, EtlSettings settings) {
        this.jdbc = jdbc;
        this.settings = settings;
    }

    /// `<idq.ora-sp.dir>/<workflow>/run_<workflow>.sql`
    public Path script(SourceSystem source) {
        return settings.oraSpDir().resolve(source.workflow).resolve("run_" + source.workflow + ".sql");
    }

    /// Procedure names of the source's run script, in the order the script executes them.
    public List<String> procedures(SourceSystem source) {
        var script = script(source);
        try {
            return Files.readAllLines(script, StandardCharsets.UTF_8).stream()
                    .map(line -> EXEC.matcher(line.strip()))
                    .filter(Matcher::matches)
                    .map(matcher -> matcher.group(1))
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException("Cannot read the ORA_SP run script " + script.toAbsolutePath(), e);
        }
    }

    /// `sp_ors_main_m_Tgt_C_S_ECI_Pty` → `m_Tgt_C_S_ECI_Pty`
    public static String mappingName(String procedure) {
        return procedure.substring(PREFIX.length());
    }

    /// Runs one procedure; a database error is returned as a `FAILED` result, never thrown.
    public MappingResult call(String procedure) {
        var started = Instant.now();
        var name = mappingName(procedure);
        if (settings.mockOraSp()) {
            return new MappingResult(name, MappingResult.Status.SUCCEEDED, 0, Map.of(), 0,
                    Duration.between(started, Instant.now()), "[mock] EXEC " + procedure);
        }
        try {
            jdbc.execute("BEGIN " + procedure + "; END;");
            return new MappingResult(name, MappingResult.Status.SUCCEEDED, 0, Map.of(), 0,
                    Duration.between(started, Instant.now()), "EXEC " + procedure);
        } catch (RuntimeException e) {
            return MappingResult.failed(name, Duration.between(started, Instant.now()), e);
        }
    }
}
