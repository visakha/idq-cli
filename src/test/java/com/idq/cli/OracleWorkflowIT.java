package com.idq.cli;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.MappingResult;
import com.idq.cli.mock.SampleData;
import com.idq.cli.workflow.MappingCatalog;
import com.idq.cli.workflow.WorkflowRunner;
import java.util.ArrayList;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

/// End-to-end check against the OCI database: for every mapping, generate mock source rows, run the mapping and
/// expect it to succeed with rows read. Needs the wallet and network, so it is not part of the default build:
///
/// ```
/// mvnw test -Dtest=OracleWorkflowIT [-Dmappings=m_Tgt_C_S_TRS_Pty_OnGoing,m_Tgt_C_S_ECI_Pty]
/// ```
@Tag("oracle")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {"spring.shell.interactive.enabled=false", "spring.shell.context.close=false"})
class OracleWorkflowIT {

    @Autowired MappingCatalog catalog;
    @Autowired SampleData sampleData;
    @Autowired WorkflowRunner runner;

    @Test
    void everyMappingRunsOnMockData() {
        var failures = new ArrayList<String>();
        var only = java.util.Set.of(System.getProperty("mappings", "").split(","));
        for (var mapping : catalog.all()) {
            if (!only.contains("") && !only.contains(mapping.info().name())) {
                continue;
            }
            try {
                sampleData.fillMock(mapping.info().name());
            } catch (RuntimeException e) {
                failures.add(mapping.info().name() + " mock data: " + e.getMessage());
                continue;
            }
            var result = runner.runMapping(mapping);
            System.out.println(result.summary());
            if (result.status() != MappingResult.Status.SUCCEEDED || result.rowsRead() == 0) {
                failures.add(result.summary());
            }
        }
        failures.forEach(f -> System.out.println("FAILURE " + f));
        assertThat(failures).isEmpty();
    }
}
