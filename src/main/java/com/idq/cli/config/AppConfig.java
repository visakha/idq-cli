package com.idq.cli.config;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.stream.Collectors;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.io.ResourceLoader;
import org.springframework.web.client.RestClient;

@Configuration
public class AppConfig {

    @Bean
    EtlSettings etlSettings(Environment env, ResourceLoader resources) {
        return new EtlSettings(
                EtlProcess.valueOf(env.getProperty("etl_process", "JAVA").trim().toUpperCase()),
                env.getProperty("mock_infacmd", Boolean.class, true),
                env.getProperty("mock_data", Boolean.class, true),
                env.getProperty("idq.mock.rows-per-table", Integer.class, 20),
                env.getProperty("idq.bootstrap-missing-objects", Boolean.class, true),
                clearableTables(resources, env.getProperty("idq.clearable-tables-file",
                        "classpath:db/clearable-tables.txt")),
                new EtlSettings.Infacmd(
                        env.getProperty("idq.infacmd.script", "docs/batch-script-windows.original.bat"),
                        env.getProperty("idq.infacmd.domain", ""),
                        env.getProperty("idq.infacmd.service", ""),
                        env.getProperty("idq.infacmd.application", "")));
    }

    @Bean
    ReportSettings reportSettings(Environment env) {
        return new ReportSettings(
                env.getProperty("idq.report.enabled", Boolean.class, true),
                Path.of(env.getProperty("idq.report.base-dir", ".")),
                Math.min(env.getProperty("idq.report.max-rows", Integer.class, 200), 1000));
    }

    @Bean
    RestClient etlRestClient(Environment env) {
        return RestClient.builder()
                .baseUrl("http://localhost:" + env.getProperty("server.port", "8085") + "/api/etl")
                .build();
    }

    private static java.util.Set<String> clearableTables(ResourceLoader resources, String location) {
        try (var in = resources.getResource(location).getInputStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8).lines()
                    .map(String::strip)
                    .filter(line -> !line.isEmpty() && !line.startsWith("#"))
                    .map(String::toUpperCase)
                    .collect(Collectors.toUnmodifiableSet());
        } catch (IOException e) {
            throw new UncheckedIOException("Cannot read clearable-tables whitelist " + location, e);
        }
    }
}
