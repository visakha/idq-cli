package com.idq.cli.workflow;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.domain.SourceSystem;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// Starts an Informatica workflow through the `infacmd` shell script (`etl_process=IDQ`).
///
/// With `mock_infacmd=true` the script is not executed; the output `infacmd wfs startWorkflow` and the polling
/// loop would print is simulated instead.
@Component
public class IdqCommandRunner {

    private final EtlSettings settings;

    public IdqCommandRunner(EtlSettings settings) {
        this.settings = settings;
    }

    public record Outcome(int exitCode, List<String> output) {}

    public Outcome startWorkflow(SourceSystem source) {
        var infacmd = settings.infacmd();
        if (settings.mockInfacmd()) {
            return new Outcome(0, List.of(
                    "[mock] infacmd.bat wfs startWorkflow -dn %s -sn %s -a %s -wf %s".formatted(infacmd.domain(),
                            infacmd.service(), infacmd.application(), source.workflow),
                    "[mock] Workflow %s started.".formatted(source.workflow),
                    "[mock] infacmd.bat wfs getWorkflowStatus ... status: COMPLETED",
                    "[mock] Workflow %s completed successfully.".formatted(source.workflow)));
        }
        var command = new ArrayList<>(List.of("cmd.exe", "/c", infacmd.script(), source.workflow));
        try {
            var process = new ProcessBuilder(command).redirectErrorStream(true).start();
            var output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8).lines().toList();
            return new Outcome(process.waitFor(), output);
        } catch (IOException e) {
            return new Outcome(-1, List.of("Cannot start " + infacmd.script() + ": " + e.getMessage()));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return new Outcome(-1, List.of("Interrupted while waiting for " + infacmd.script()));
        }
    }
}
