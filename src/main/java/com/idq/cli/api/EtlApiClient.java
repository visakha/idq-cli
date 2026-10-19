package com.idq.cli.api;

import com.idq.cli.cli.EtlConsole;
import java.util.List;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/// Programmatic client of [EtlController] built on Spring's `RestClient`, for automation and integration with other
/// systems:
///
/// ```java
/// client.latchSource("TRS");
/// client.latchTarget("C_S_TRS_PTY");
/// client.latchMapping("m_Tgt_C_S_TRS_Pty_OnGoing");
/// client.fillMock();
/// client.runEtl();
/// ```
@Component
public class EtlApiClient {

    private final RestClient rest;

    public EtlApiClient(RestClient etlRestClient) {
        this.rest = etlRestClient;
    }

    public List<EtlConsole.CommandHelp> menu() {
        return rest.get().uri("/menu").retrieve().body(new ParameterizedTypeReference<>() {});
    }

    public EtlController.Latches latches() {
        return rest.get().uri("/latch").retrieve().body(EtlController.Latches.class);
    }

    public EtlController.Message latchSource(String source) {
        return post("/latch/source/{v}", source);
    }

    public EtlController.Message latchTarget(String table) {
        return post("/latch/target/{v}", table);
    }

    public EtlController.Message latchMapping(String mapping) {
        return post("/latch/mapping/{v}", mapping);
    }

    public List<EtlConsole.MappingView> sourceMappings() {
        return rest.get().uri("/source-mappings").retrieve().body(new ParameterizedTypeReference<>() {});
    }

    public EtlController.Message fillMock() {
        return rest.post().uri("/sample-data/mock").retrieve().body(EtlController.Message.class);
    }

    public String runEtl() {
        return rest.post().uri("/run").retrieve().body(String.class);
    }

    public String runUnitTests() {
        return rest.post().uri("/unit-tests").retrieve().body(String.class);
    }

    private EtlController.Message post(String uri, String value) {
        return rest.post().uri(uri, value).retrieve().body(EtlController.Message.class);
    }
}
