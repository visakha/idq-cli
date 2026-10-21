package com.idq.cli.workflow;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import com.idq.cli.config.SnowflakeSettings;
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
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.stereotype.Component;

/// Calls the Snowflake stored procedures that replace the IDQ mappings (`etl_process=SNOWFLAKE_SP`).
///
/// The procedures and their order come from the workflow's run script,
/// `<idq.snowflake-sp.dir>/<workflow>/run_<workflow>.sql` (its `CALL sp_snow_main_<mapping>();` lines, in taskflow
/// order). Each procedure is one transaction: it commits on success and rolls back and re-raises on error, and it
/// returns its run log, which becomes the result message. With `mock_snowflake_sp=true` nothing is called; the `CALL`
/// that would run is reported instead.
///
/// The connection is separate from the Oracle data source of the rest of the CLI ([SnowflakeSettings]) and is opened
/// only when a procedure is really called.
@Component
public class SnowflakeSpRunner implements StoredProcedureRunner {

    static final String PREFIX = "sp_snow_main_";
    private static final Pattern CALL = Pattern.compile("^CALL\\s+(" + PREFIX + "\\w+)\\s*\\(\\s*\\)\\s*;?\\s*$",
            Pattern.CASE_INSENSITIVE);

    private final EtlSettings settings;
    private final SnowflakeSettings snowflake;
    private JdbcTemplate jdbc;

    public SnowflakeSpRunner(EtlSettings settings, SnowflakeSettings snowflake) {
        this.settings = settings;
        this.snowflake = snowflake;
    }

    @Override
    public EtlProcess engine() {
        return EtlProcess.SNOWFLAKE_SP;
    }

    /// `<idq.snowflake-sp.dir>/<workflow>/run_<workflow>.sql`
    public Path script(SourceSystem source) {
        return settings.snowflakeSpDir().resolve(source.workflow).resolve("run_" + source.workflow + ".sql");
    }

    /// Procedure names of the source's run script, in the order the script calls them.
    @Override
    public List<String> procedures(SourceSystem source) {
        var script = script(source);
        try {
            return Files.readAllLines(script, StandardCharsets.UTF_8).stream()
                    .map(line -> CALL.matcher(line.strip()))
                    .filter(Matcher::matches)
                    .map(matcher -> matcher.group(1))
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException("Cannot read the SNOWFLAKE_SP run script " + script.toAbsolutePath(), e);
        }
    }

    /// `sp_snow_main_m_Tgt_C_S_ECI_Pty` → `m_Tgt_C_S_ECI_Pty`
    public static String mappingName(String procedure) {
        return procedure.substring(PREFIX.length());
    }

    @Override
    public String mapping(String procedure) {
        return mappingName(procedure);
    }

    @Override
    public MappingResult call(String procedure) {
        var started = Instant.now();
        var name = mappingName(procedure);
        if (settings.mockSnowflakeSp()) {
            return new MappingResult(name, MappingResult.Status.SUCCEEDED, 0, Map.of(), 0,
                    Duration.between(started, Instant.now()), "[mock] CALL " + procedure + "()");
        }
        if (!snowflake.configured()) {
            return MappingResult.failed(name, Duration.between(started, Instant.now()), new IllegalStateException(
                    "idq.snowflake.url is not set (environment variable SNOWFLAKE_JDBC_URL)"));
        }
        try {
            var log = jdbc().queryForObject("CALL " + procedure + "()", String.class);
            return new MappingResult(name, MappingResult.Status.SUCCEEDED, 0, Map.of(), 0,
                    Duration.between(started, Instant.now()), "CALL " + procedure + "(): " + log);
        } catch (RuntimeException e) {
            return MappingResult.failed(name, Duration.between(started, Instant.now()), e);
        }
    }

    private synchronized JdbcTemplate jdbc() {
        if (jdbc == null) {
            jdbc = new JdbcTemplate(new DriverManagerDataSource(snowflake.url(), snowflake.user(),
                    snowflake.password()));
        }
        return jdbc;
    }
}
