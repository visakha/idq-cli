package com.idq.cli;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.MappingResult;
import com.idq.cli.config.ReportSettings;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mock.SampleData;
import com.idq.cli.workflow.MappingCatalog;
import com.idq.cli.workflow.WorkflowRunner;
import java.nio.file.Files;
import java.util.ArrayList;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.util.FileSystemUtils;

/// End-to-end check against the OCI database: for every mapping, generate mock source rows, run the mapping and
/// expect it to succeed with rows read. Needs the wallet and network, so it is not part of the default build:
///
/// ```
/// mvnw test -Dtest=OracleWorkflowIT [-Dmappings=m_Tgt_C_S_TRS_Pty_OnGoing,m_Tgt_C_S_ECI_Pty]
/// ```
@Tag("oracle")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {"spring.shell.interactive.enabled=false", "spring.shell.context.close=false",
                "idq.report.base-dir=target/adhoc-it", "mock-data-pre-fix=Test_001"})
class OracleWorkflowIT {

    @Autowired MappingCatalog catalog;
    @Autowired SampleData sampleData;
    @Autowired WorkflowRunner runner;
    @Autowired ReportSettings reports;

    /// `run-etl` for ECI on mock data (prefixed `Test_001`): every target table gets an audit report whose sections
    /// could all be read, plus the `.sql` that replays the mock data.
    ///
    /// ```
    /// mvnw test -Dtest=OracleWorkflowIT#runWritesAuditReports [-Dsource=TRS]
    /// ```
    @Test
    void runWritesAuditReports() throws Exception {
        var source = SourceSystem.valueOf(System.getProperty("source", "ECI"));
        FileSystemUtils.deleteRecursively(reports.dirFor(source));
        sampleData.fillMockAll(catalog.of(source).stream().map(m -> m.info().name()).toList());
        var run = runner.run(source);
        run.output().forEach(System.out::println);
        try (var files = Files.list(reports.dirFor(source))) {
            var reportFiles = files.filter(f -> f.getFileName().toString().endsWith(".md")).toList();
            assertThat(reportFiles).isNotEmpty();
            var prefixed = 0;
            for (var file : reportFiles) {
                var md = Files.readString(file);
                assertThat(md).as(file.toString()).doesNotContain("could not be read");
                prefixed += md.contains("Test_001-") ? 1 : 0;
                var sql = file.resolveSibling(file.getFileName().toString().replace(".md", ".sql"));
                assertThat(sql).exists();
                assertThat(Files.readString(sql)).contains("INSERT INTO");
            }
            assertThat(prefixed).isPositive();
        }
    }

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
