package com.idq.cli.mock;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// `mock-data-pre-fix` handling and the SQL recorded for the audit reports.
class MockTablesTest {

    @Test
    void freeTextGetsThePrefix() {
        assertThat(MockTables.prefixed("Test_001", "JaneDoe@gmail.com", 125)).isEqualTo("Test_001-JaneDoe@gmail.com");
        assertThat(MockTables.prefixed("", "JaneDoe@gmail.com", 125)).isEqualTo("JaneDoe@gmail.com");
    }

    @Test
    void prefixedTextIsCutToTheColumnLengthKeepingThePrefix() {
        assertThat(MockTables.prefixed("Test_001", "Christopher", 15)).isEqualTo("Test_001-Christ");
    }

    @Test
    void statementsAreRecordedWithLiteralValues() {
        var params = new LinkedHashMap<String, Object>();
        params.put("ID", 9100000001L);
        params.put("NAME", "O'Hara");
        params.put("DOB", LocalDateTime.of(2020, 5, 1, 8, 30));
        params.put("MID", null);
        assertThat(MockTables.sql("INSERT INTO T (ID, NAME, DOB, MID) VALUES (:ID, :NAME, :DOB, :MID)", params))
                .isEqualTo("INSERT INTO T (ID, NAME, DOB, MID) VALUES (9100000001, 'O''Hara', "
                        + "TIMESTAMP '2020-05-01 08:30:00', NULL);");
        assertThat(MockTables.sql("DELETE FROM T WHERE ID LIKE '9100000___'", Map.of()))
                .isEqualTo("DELETE FROM T WHERE ID LIKE '9100000___';");
    }
}
