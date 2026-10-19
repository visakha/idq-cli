package com.idq.cli.config;

import com.idq.cli.domain.SourceSystem;
import java.nio.file.Path;

/// Switches of the adhoc-run audit reports.
///
/// | property                 | field        |
/// |--------------------------|--------------|
/// | `idq.report.enabled`     | [#enabled]   |
/// | `idq.report.base-dir`    | [#baseDir]   |
/// | `idq.report.max-rows`    | [#maxRows]   |
///
/// @param maxRows rows shown per table section; the total row count is always reported
public record ReportSettings(boolean enabled, Path baseDir, int maxRows) {

    /// `<base-dir>/adhoc_runs_<SOURCE>`
    public Path dirFor(SourceSystem source) {
        return baseDir.resolve("adhoc_runs_" + source.name());
    }
}
