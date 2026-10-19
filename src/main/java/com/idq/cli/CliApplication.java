package com.idq.cli;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jdbc.repository.config.EnableJdbcRepositories;

/// IDQ replacement ETL: interactive shell plus REST API over the Java re-implementation of the Informatica IDQ
/// Member workflows. See `README.md`.
@SpringBootApplication
@EnableJdbcRepositories(considerNestedRepositories = true)
public class CliApplication {

    public static void main(String[] args) {
        SpringApplication.run(CliApplication.class, args);
    }
}
