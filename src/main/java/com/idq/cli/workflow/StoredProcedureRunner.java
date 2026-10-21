package com.idq.cli.workflow;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.core.MappingResult;
import com.idq.cli.domain.SourceSystem;
import java.util.List;

/// An engine whose mappings are database stored procedures called in the order of a run script
/// (`etl_process=ORA_SP`: [OraSpRunner], `etl_process=SNOWFLAKE_SP`: [SnowflakeSpRunner]).
public interface StoredProcedureRunner {

    EtlProcess engine();

    /// Procedure names of the source's run script, in the order the script runs them.
    List<String> procedures(SourceSystem source);

    /// The IDQ mapping a procedure replaces (the procedure name without its prefix).
    String mapping(String procedure);

    /// Runs one procedure; a database error is returned as a `FAILED` result, never thrown.
    MappingResult call(String procedure);
}
