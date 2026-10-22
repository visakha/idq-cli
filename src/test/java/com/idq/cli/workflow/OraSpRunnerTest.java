package com.idq.cli.workflow;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.SourceSystem;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

/// The `etl_process=ORA_SP` procedure list read from the `idq-to-oracle/<workflow>/run_<workflow>.sql` scripts.
class OraSpRunnerTest {

    static OraSpRunner runner(boolean mock) {
        return new OraSpRunner(null, new EtlSettings(EtlProcess.ORA_SP, true, mock, true, true, 20, "", true, null,
                Path.of("idq-to-oracle"), Path.of("idq-to-snowflake")));
    }

    @Test
    void readsTheEciProceduresInTaskflowOrder() {
        assertThat(runner(true).procedures(SourceSystem.ECI)).containsExactly(
                "sp_ors_main_m_Tgt_C_S_ECI_Pty_Validation",
                "sp_ors_main_m_Tgt_C_S_ECI_Pty",
                "sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr",
                "sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn",
                "sp_ors_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid",
                "sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id",
                "sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr",
                "sp_ors_main_m_Tgt_C_S_ECI_Pty_Addr",
                "sp_ors_main_m_Tgt_C_S_ECI_Pty_Rle_Rel");
    }

    /// TRS runs its second workflow, `wf_TRS_Stage_Load_TOA`, after the Ongoing one.
    @Test
    void trsRunsTheToaWorkflowLast() {
        var procedures = runner(true).procedures(SourceSystem.TRS);
        assertThat(procedures).hasSize(15).last().isEqualTo("sp_ors_main_m_Tgt_C_S_TRS_Stg_TOA");
    }

    @ParameterizedTest
    @EnumSource(SourceSystem.class)
    void everySourceHasARunScript(SourceSystem source) {
        assertThat(runner(true).procedures(source)).isNotEmpty().allMatch(p -> p.startsWith(OraSpRunner.PREFIX));
    }

    @Test
    void mockCallReportsTheExecWithoutTouchingTheDatabase() {
        var result = runner(true).call("sp_ors_main_m_Tgt_C_S_ECI_Pty");
        assertThat(result.mapping()).isEqualTo("m_Tgt_C_S_ECI_Pty");
        assertThat(result.status()).isEqualTo(MappingResult.Status.SUCCEEDED);
        assertThat(result.message()).isEqualTo("[mock] EXEC sp_ors_main_m_Tgt_C_S_ECI_Pty");
    }
}
