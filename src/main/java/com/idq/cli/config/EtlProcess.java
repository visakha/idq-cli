package com.idq.cli.config;

/// Which engine executes a workflow, selected by the `etl_process` property.
public enum EtlProcess {
    /// Informatica IDQ, started through the `infacmd` shell script.
    IDQ,
    /// The Java re-implementation in this application (default).
    JAVA
}
