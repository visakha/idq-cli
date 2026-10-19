package com.idq.cli.core.target;

/// Creates the source-specific entity for a sub-domain row, e.g. `TrsTargets.Phone::new`.
@FunctionalInterface
public interface RowFactory<C extends Columns, R extends StagingRow<C>> {

    R create(String pkeySrcObject, MdmAudit audit, C columns);
}
