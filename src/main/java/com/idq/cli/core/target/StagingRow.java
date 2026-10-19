package com.idq.cli.core.target;

/// A row of a source-specific `C_S_*` table: the formulated key, the common MDM columns and one column group.
///
/// Implementations are tiny `@Table` records in the source packages; everything else is generic.
public interface StagingRow<C extends Columns> {

    String pkeySrcObject();

    MdmAudit audit();

    C columns();
}
