package com.idq.cli.api;

import com.idq.cli.cli.EtlConsole;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.Domain;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.workflow.EtlCompareRunner;
import com.idq.cli.workflow.WorkflowRunner;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/// REST mirror of the CLI. Latches are shared with the shell session.
///
/// | CLI command             | HTTP                                   |
/// |-------------------------|----------------------------------------|
/// | show-menu               | `GET /api/etl/menu`                    |
/// | show-domains            | `GET /api/etl/domains`                 |
/// | show-sources            | `GET /api/etl/sources`                 |
/// | latch-source-system X   | `POST /api/etl/latch/source/X`         |
/// | unlatch-source-system   | `DELETE /api/etl/latch/source`         |
/// | show-latched-source     | `GET /api/etl/latch`                   |
/// | latch-domain X          | `POST /api/etl/latch/domain/X`         |
/// | unlatch-domain X        | `DELETE /api/etl/latch/domain/X`       |
/// | show-latched-domains    | `GET /api/etl/latch`                   |
/// | latch-target-table X    | `POST /api/etl/latch/target/X`         |
/// | unlatch-target-table    | `DELETE /api/etl/latch/target`         |
/// | show-source-mapping     | `GET /api/etl/source-mappings`         |
/// | latch-mapping X         | `POST /api/etl/latch/mapping/X`        |
/// | unlatch-mapping         | `DELETE /api/etl/latch/mapping`        |
/// | show-sample-data        | `GET /api/etl/sample-data?limit=10`    |
/// | fill-sample-mock-data   | `POST /api/etl/sample-data/mock`       |
/// | fill-sample-real-data   | `POST /api/etl/sample-data/real`       |
/// | run-etl                 | `POST /api/etl/run`                    |
/// | (single mapping)        | `POST /api/etl/run/mapping`            |
/// | run-unit-tests          | `POST /api/etl/unit-tests`             |
/// | compare-etl-process X   | `POST /api/etl/compare/X`              |
@RestController
@RequestMapping("/api/etl")
public class EtlController {

    private final EtlConsole console;

    public EtlController(EtlConsole console) {
        this.console = console;
    }

    public record Message(String message) {}

    public record Latches(String context, String source, String targetTable, String mapping,
            java.util.Set<Domain> domains) {}

    @GetMapping("/menu")
    public List<EtlConsole.CommandHelp> menu() {
        return EtlConsole.MENU;
    }

    @GetMapping("/domains")
    public Map<Domain, Map<SubDomain, List<String>>> domains() {
        return console.domains();
    }

    @GetMapping("/sources")
    public List<EtlConsole.SourceView> sources() {
        return console.sources();
    }

    @GetMapping("/latch")
    public Latches latches() {
        var latch = console.latch();
        return new Latches(latch.context(), latch.source().map(Enum::name).orElse(null),
                latch.targetTable().orElse(null), latch.mapping().orElse(null), latch.domains());
    }

    @PostMapping("/latch/source/{source}")
    public Message latchSource(@PathVariable String source) {
        return new Message(console.latchSource(source));
    }

    @DeleteMapping("/latch/source")
    public Message unlatchSource() {
        return new Message(console.unlatchSource());
    }

    @PostMapping("/latch/domain/{domain}")
    public Message latchDomain(@PathVariable String domain) {
        return new Message(console.latchDomain(domain));
    }

    @DeleteMapping("/latch/domain/{domain}")
    public Message unlatchDomain(@PathVariable String domain) {
        return new Message(console.unlatchDomain(domain));
    }

    @PostMapping("/latch/target/{table}")
    public Message latchTarget(@PathVariable String table) {
        return new Message(console.latchTargetTable(table));
    }

    @DeleteMapping("/latch/target")
    public Message unlatchTarget() {
        return new Message(console.unlatchTargetTable());
    }

    @GetMapping("/source-mappings")
    public List<EtlConsole.MappingView> sourceMappings() {
        return console.sourceMappings();
    }

    @PostMapping("/latch/mapping/{mapping}")
    public Message latchMapping(@PathVariable String mapping) {
        return new Message(console.latchMapping(mapping));
    }

    @DeleteMapping("/latch/mapping")
    public Message unlatchMapping() {
        return new Message(console.unlatchMapping());
    }

    @GetMapping("/sample-data")
    public List<?> sampleData(@RequestParam(defaultValue = "10") int limit) {
        return console.sampleData(limit);
    }

    @PostMapping("/sample-data/mock")
    public Message fillMock() {
        return new Message(console.fillSampleMockData());
    }

    @PostMapping("/sample-data/real")
    public Message fillReal() {
        return new Message(console.fillSampleRealData());
    }

    @PostMapping("/run")
    public WorkflowRunner.WorkflowRun runEtl() {
        return console.runEtl();
    }

    @PostMapping("/run/mapping")
    public MappingResult runMapping() {
        return console.runLatchedMapping();
    }

    @PostMapping("/compare/{source}")
    public EtlCompareRunner.Comparison compare(@PathVariable String source) {
        return console.compareEtlProcesses(source);
    }

    @PostMapping("/unit-tests")
    public EtlConsole.TestRun runUnitTests() {
        return console.runUnitTests();
    }

    @ExceptionHandler({IllegalStateException.class, IllegalArgumentException.class})
    public ResponseEntity<Message> badRequest(RuntimeException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(new Message(e.getMessage()));
    }
}
