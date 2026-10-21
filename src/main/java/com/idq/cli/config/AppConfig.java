package com.idq.cli.config;

import java.nio.file.Path;
import java.util.stream.Collectors;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.web.client.RestClient;

@Configuration
public class AppConfig {

    @Bean
    EtlSettings etlSettings(Environment env) {
        return new EtlSettings(
                EtlProcess.valueOf(env.getProperty("etl_process", "JAVA").trim().toUpperCase()),
                env.getProperty("mock_infacmd", Boolean.class, true),
                env.getProperty("mock_ora_sp", Boolean.class, true),
                env.getProperty("mock_snowflake_sp", Boolean.class, true),
                env.getProperty("mock_data", Boolean.class, true),
                env.getProperty("idq.mock.rows-per-table", Integer.class, 20),
                env.getProperty("mock-data-pre-fix", "").strip(),
                env.getProperty("idq.bootstrap-missing-objects", Boolean.class, true),
                new EtlSettings.Infacmd(
                        env.getProperty("idq.infacmd.script", "docs/batch-script-windows.original.bat"),
                        env.getProperty("idq.infacmd.domain", ""),
                        env.getProperty("idq.infacmd.service", ""),
                        env.getProperty("idq.infacmd.application", "")),
                Path.of(env.getProperty("idq.ora-sp.dir", "idq-to-oracle")),
                Path.of(env.getProperty("idq.snowflake-sp.dir", "idq-to-snowflake")));
    }

    @Bean
    SnowflakeSettings snowflakeSettings(Environment env) {
        return new SnowflakeSettings(
                env.getProperty("idq.snowflake.url", "").strip(),
                env.getProperty("idq.snowflake.user", "").strip(),
                env.getProperty("idq.snowflake.password", ""));
    }

    @Bean
    ReportSettings reportSettings(Environment env) {
        return new ReportSettings(
                env.getProperty("idq.report.enabled", Boolean.class, true),
                Path.of(env.getProperty("idq.report.base-dir", ".")),
                Math.min(env.getProperty("idq.report.max-rows", Integer.class, 200), 1000));
    }

    @Bean
    CompareSettings compareSettings(Environment env) {
        var ignore = env.getProperty("idq.compare.ignore-columns",
                "ROWID_OBJECT,CREATE_DATE,LAST_UPDATE_DATE,CREATOR,UPDATED_BY,PERIOD_START_DATE,PERIOD_END_DATE");
        return new CompareSettings(
                java.util.Arrays.stream(ignore.split(","))
                        .map(String::strip)
                        .filter(column -> !column.isEmpty())
                        .map(String::toUpperCase)
                        .collect(Collectors.toUnmodifiableSet()));
    }

    @Bean
    RestClient etlRestClient(Environment env) {
        return RestClient.builder()
                .baseUrl("http://localhost:" + env.getProperty("server.port", "8085") + "/api/etl")
                .build();
    }
}
