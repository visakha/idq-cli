package com.idq.cli.core.audit;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.ReportSettings;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingResult;
import com.idq.cli.core.audit.EtlEvent.RowSample;
import com.idq.cli.core.audit.EtlEvent.RunId;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.EciTargets;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyRelation;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.eci.etlmap.svc.EciPkeyTest;
import com.idq.cli.source.eci.etlmap.svc.EciRelationshipService;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/// The audit report of a Java run of `m_Tgt_C_S_ECI_Pty_Rle_Rel`, built from the events the workflow publishes.
class AdhocRunReporterTest {

    @TempDir
    Path dir;

    final RunId run = new RunId(SourceSystem.ECI, EtlProcess.JAVA, LocalDateTime.of(2026, 10, 19, 9, 54, 12));

    @Test
    void writesOneMarkdownReportPerTargetTable() throws Exception {
        var reporter = new AdhocRunReporter(new ReportSettings(true, dir, 200));
        var info = EciRelationshipService.INFO;
        var relation = new FamilyRelation("To Child", 7L, "F", 42L, "1", DAY, DAY);
        var output = EciPkeyTest.relationships().transform(List.of(relation),
                new EciRelationshipService.Lookups(InactiveStatus.Lookup.NONE, Map.of()), ctx(info));
        var family = EciSources.FamilyDelta.builder().idFamily(7L).idChild(42L).familyCd(1).gender("F")
                .firstName("Mia").lastName("Lee").dob(DAY).childResidesInd(1).inactiveInd(0).dateCreated(DAY)
                .modifiedBy("mock").createdBy("mock").loadDate(DAY).build();

        reporter.on(new EtlEvent.RunStarted(run));
        reporter.on(new EtlEvent.SourceTablesCaptured(run, info, List.of(
                new RowSample("STG_ECI_D_FAMILY", EciSources.FamilyDelta.class, 1, List.of(family), "before"),
                new RowSample("STG_ECI_SN_CHILD", EciSources.SnChild.class, 0, List.of(), "before"))));
        reporter.on(new EtlEvent.InitQueryCaptured(run, info,
                new RowSample("IdqMapInitQuery", FamilyRelation.class, 1, List.of(relation), "returned")));
        reporter.on(new EtlEvent.TargetsWritten(run, info, List.of(new RowSample("C_S_ECI_PTY_RLE_REL",
                EciTargets.Relationship.class, 1, output.rows(EciTargets.Relationship.class), "read back"))));
        reporter.on(new EtlEvent.MappingFinished(run, info, new MappingResult(info.name(),
                MappingResult.Status.SUCCEEDED, 1, Map.of("C_S_ECI_PTY_RLE_REL", 1), 0, Duration.ofMillis(5), null)));
        reporter.on(new EtlEvent.RunCompleted(run, List.of()));

        var report = dir.resolve("adhoc_runs_ECI").resolve("C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_9_54_AM.md");
        assertThat(report).exists();
        var md = Files.readString(report);
        assertThat(md)
                .contains("# C_S_ECI_PTY_RLE_REL - ECI adhoc run (Java)")
                .contains("| 018 | m_Tgt_C_S_ECI_Pty_Rle_Rel | SUCCEEDED | 1 | C_S_ECI_PTY_RLE_REL=1 | 0 | 5 |  |")
                .contains("#### STG_ECI_D_FAMILY (`EciSources.FamilyDelta`)", "| ID_FAMILY | ID_CHILD | FAMILY_CD |")
                .contains("| 7 | 42 | 1 | F |  |  | Mia | Lee |", "#### STG_ECI_SN_CHILD", "_no rows_")
                .contains("### IdqMapInitQuery (`EciQueryRows.FamilyRelation`)",
                        "| RELATION_DIRECTION | ID_FAMILY | FAMILY_GENDER | ID_CHILD |", "| To Child | 7 | F | 42 |")
                .contains("#### C_S_ECI_PTY_RLE_REL (`EciTargets.Relationship`)", "| PKEY_SRC_OBJECT |",
                        "PTY_RLE_FK_1", "| 0000000007F\\|Member\\|0000000042\\|Member\\|MTH |")
                .doesNotContain("$");
        assertThat(md.chars().allMatch(c -> c < 128)).isTrue();
    }

    @Test
    void mockDataOfTheRunIsWrittenAsSqlNextToTheReport() throws Exception {
        var reporter = new AdhocRunReporter(new ReportSettings(true, dir, 200));
        var info = EciRelationshipService.INFO;
        reporter.on(new MockDataGenerated(MockDataGenerated.REFERENCE_DATA, "Test_001",
                List.of("INSERT INTO LOOKUP_CODE_VALUE (CODE_TYPE) VALUES ('REL_TP');")));
        reporter.on(new MockDataGenerated(info.name(), "Test_001", List.of(
                "DELETE FROM STG_ECI_D_FAMILY WHERE ID_FAMILY BETWEEN 9100000000 AND 9100999999;",
                "INSERT INTO STG_ECI_D_FAMILY (ID_FAMILY, FIRST_NAME) VALUES (9100000001, 'Test_001-Mia');")));

        for (var second : List.of(false, true)) {
            var started = run.started().plusMinutes(second ? 1 : 0);
            var thisRun = new RunId(SourceSystem.ECI, EtlProcess.JAVA, started);
            reporter.on(new EtlEvent.RunStarted(thisRun));
            reporter.on(new EtlEvent.MappingFinished(thisRun, info, new MappingResult(info.name(),
                    MappingResult.Status.SUCCEEDED, 0, Map.of(), 0, Duration.ZERO, null)));
            reporter.on(new EtlEvent.RunCompleted(thisRun, List.of()));
        }

        var reports = dir.resolve("adhoc_runs_ECI");
        var sql = reports.resolve("C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_9_54_AM.sql");
        assertThat(Files.readString(sql))
                .contains("-- mock-data-pre-fix: Test_001", "-- reference data (ReferenceMockData.seed)",
                        "INSERT INTO LOOKUP_CODE_VALUE (CODE_TYPE) VALUES ('REL_TP');",
                        "-- fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Rel",
                        "VALUES (9100000001, 'Test_001-Mia');")
                .endsWith("COMMIT;\n");
        assertThat(Files.readString(reports.resolve("C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_9_54_AM.md")))
                .contains("| mock data SQL | `C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_9_54_AM.sql` |");
        assertThat(reports.resolve("C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_9_55_AM.sql")).doesNotExist();
        assertThat(Files.readString(reports.resolve("C_S_ECI_PTY_RLE_REL_$Java$_19_10_2026_9_55_AM.md")))
                .contains("| mock data SQL | none (no mock data generated for these mappings) |");
    }

    @Test
    void sameMinuteRunsDoNotOverwriteEachOther() throws Exception {
        var reporter = new AdhocRunReporter(new ReportSettings(true, dir, 200));
        var first = reporter.file(run, "C_S_ECI_PTY");
        Files.createDirectories(first.getParent());
        Files.writeString(first, "earlier run");
        assertThat(reporter.file(run, "C_S_ECI_PTY").getFileName())
                .hasToString("C_S_ECI_PTY_$Java$_19_10_2026_9_54_AM_2.md");
    }
}
