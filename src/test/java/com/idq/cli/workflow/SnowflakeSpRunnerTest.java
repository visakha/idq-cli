package com.idq.cli.workflow;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import com.idq.cli.config.SnowflakeSettings;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.SourceSystem;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/// The `etl_process=SNOWFLAKE_SP` procedure list read from the `idq-to-snowflake/<workflow>/run_<workflow>.sql`
/// scripts, and the consistency of those scripts with the procedure files and `install.sql`.
class SnowflakeSpRunnerTest {

    static SnowflakeSpRunner runner(boolean mock, SnowflakeSettings snowflake) {
        return new SnowflakeSpRunner(new EtlSettings(EtlProcess.SNOWFLAKE_SP, true, true, mock, true, 20, "", true,
                null, Path.of("idq-to-oracle"), Path.of("idq-to-snowflake")), snowflake);
    }

    static SnowflakeSpRunner runner(boolean mock) {
        return runner(mock, new SnowflakeSettings("", "", ""));
    }

    @Test
    void readsTheEciProceduresInTaskflowOrder() {
        assertThat(runner(true).procedures(SourceSystem.ECI)).containsExactly(
                "sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation",
                "sp_snow_main_m_Tgt_C_S_ECI_Pty",
                "sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr",
                "sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn",
                "sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid",
                "sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id",
                "sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr",
                "sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr",
                "sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel");
    }

    /// Same mappings, same order as the Oracle port: both replace the same IDQ taskflow.
    @ParameterizedTest
    @EnumSource(SourceSystem.class)
    void runsTheSameMappingsAsTheOracleScript(SourceSystem source) {
        var oracle = OraSpRunnerTest.runner(true).procedures(source).stream().map(OraSpRunner::mappingName).toList();
        var snowflake = runner(true).procedures(source).stream().map(SnowflakeSpRunner::mappingName).toList();
        assertThat(snowflake).isNotEmpty().isEqualTo(oracle);
    }

    @ParameterizedTest
    @EnumSource(SourceSystem.class)
    void everyCalledProcedureHasItsFileAndIsInstalled(SourceSystem source) throws IOException {
        var install = Files.readString(Path.of("idq-to-snowflake", "install.sql"));
        for (var procedure : runner(true).procedures(source)) {
            var workflow = source.workflows.stream()
                    .filter(wf -> Files.exists(Path.of("idq-to-snowflake", wf, procedure + ".sql"))).findFirst();
            assertThat(workflow).as("workflow folder of %s", procedure).isPresent();
            var file = workflow.get() + "/" + procedure + ".sql";
            assertThat(install).contains("!source " + file);
            assertThat(Files.readString(Path.of("idq-to-snowflake", file)))
                    .containsPattern(Pattern.compile("CREATE OR REPLACE PROCEDURE " + procedure + "\\s*\\("));
        }
    }

    @Test
    void mockCallReportsTheCallWithoutTouchingTheDatabase() {
        var result = runner(true).call("sp_snow_main_m_Tgt_C_S_ECI_Pty");
        assertThat(result.mapping()).isEqualTo("m_Tgt_C_S_ECI_Pty");
        assertThat(result.status()).isEqualTo(MappingResult.Status.SUCCEEDED);
        assertThat(result.message()).isEqualTo("[mock] CALL sp_snow_main_m_Tgt_C_S_ECI_Pty()");
    }

    @Test
    void realCallWithoutAConnectionFailsInsteadOfThrowing() {
        var result = runner(false).call("sp_snow_main_m_Tgt_C_S_ECI_Pty");
        assertThat(result.status()).isEqualTo(MappingResult.Status.FAILED);
        assertThat(result.message()).contains("SNOWFLAKE_JDBC_URL");
    }

    @Test
    void settingsNeverPrintThePassword() {
        assertThat(new SnowflakeSettings("jdbc:snowflake://x", "etl", "secret").toString())
                .doesNotContain("secret").contains("***");
    }
}
