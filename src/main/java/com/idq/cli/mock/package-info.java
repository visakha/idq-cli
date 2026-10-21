/// Mock source rows (Datafaker) and the reference-data seed, for running mappings without real data.
///
/// Why it exists: the source tables are often empty or unsuitable in development. `fill-sample-mock-data` calls the
/// generator function `fill_sample_mock_data_<mapping>` ([SampleData]), which writes rows in reserved id ranges and
/// deliberately includes invalid rows so the exception paths run. [MockTables] records every statement so the audit
/// report can ship it as SQL. Reference data is seeded by [ReferenceMockData].
package com.idq.cli.mock;
