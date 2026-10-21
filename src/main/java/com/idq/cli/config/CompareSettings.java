package com.idq.cli.config;

import java.util.Set;

/// Switches of `compare-etl-process` (ORA_SP vs IDQ on the same source data).
///
/// | property                          | field              |
/// |-----------------------------------|--------------------|
/// | `idq.compare.ignore-columns`      | [#ignoreColumns]   |
///
/// @param ignoreColumns columns left out of the target comparison because they differ on every run (audit
///                      timestamps, creator, MDM-owned keys); upper case
public record CompareSettings(Set<String> ignoreColumns) {

    public boolean compared(String column) {
        return !ignoreColumns.contains(column.toUpperCase());
    }
}
