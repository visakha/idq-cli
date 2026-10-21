package com.idq.cli.core;

import java.util.Map;

/// A mapping that loads its targets through its own Spring Data JDBC repositories (`source.<src>.etldb.repo`) rather
/// than the generic [com.idq.cli.core.target.TargetWriter]. Sources not yet migrated to `etldb` keep the writer.
public interface TargetLoad {

    /// @return rows inserted (or deleted) per table, in load order
    Map<String, Integer> load(MappingOutput output);
}
