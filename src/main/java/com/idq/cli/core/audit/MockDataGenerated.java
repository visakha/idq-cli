package com.idq.cli.core.audit;

import java.util.List;

/// Published after a mock-data function ran: the SQL it executed, so that the next run's audit reports can ship a
/// replayable `.sql` file next to the Markdown.
///
/// @param group      mapping name for `fill_sample_mock_data_<mapping>`, or [#REFERENCE_DATA] for the lookup seed
/// @param prefix     the `mock-data-pre-fix` in effect, empty when none
/// @param statements `DELETE` / `INSERT` statements with literal values, each terminated by `;`
public record MockDataGenerated(String group, String prefix, List<String> statements) {

    public static final String REFERENCE_DATA = "reference data";
}
