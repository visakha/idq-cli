package com.idq.cli.config;

/// Which engine executes a workflow, selected by the `etl_process` property.
public enum EtlProcess {
    /// Informatica IDQ, started through the `infacmd` shell script.
    IDQ,
    /// The Oracle stored procedures of `idq-to-oracle/` (`sp_ors_main_<mapping>`), called over JDBC in the order of
    /// the workflow's `run_<workflow>.sql`.
    ORA_SP,
    /// The Snowflake stored procedures of `idq-to-snowflake/` (`sp_snow_main_<mapping>`), called over the Snowflake
    /// JDBC driver in the order of the workflow's `run_<workflow>.sql`.
    SNOWFLAKE_SP,
    /// The Java re-implementation in this application (default).
    JAVA
}
