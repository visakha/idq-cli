package com.idq.cli.mock;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.config.EtlProcess;
import com.idq.cli.config.EtlSettings;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import org.junit.jupiter.api.Test;

/// `mock-data-pre-fix` handling and the SQL recorded for the audit reports.
class MockTablesTest {

    static MockTables tables(String prefix) {
        return new MockTables(null, null, new EtlSettings(EtlProcess.JAVA, true, true, true, 20, prefix, true,
                null, null));
    }

    @Test
    void freeTextGetsThePrefix() {
        assertThat(tables("Test_001").text("JaneDoe@gmail.com")).isEqualTo("Test_001-JaneDoe@gmail.com");
        assertThat(tables("").text("JaneDoe@gmail.com")).isEqualTo("JaneDoe@gmail.com");
        assertThat(tables("Test_001").text(null)).isNull();
    }

    @Test
    void prefixedTextIsCutToTheColumnLengthKeepingThePrefix() {
        assertThat(MockTables.fit("Test_001-Christopher", 15)).isEqualTo("Test_001-Christ");
        assertThat(MockTables.fit("Test_001-Mia", 15)).isEqualTo("Test_001-Mia");
    }

    @Test
    void statementsAreRecordedWithLiteralValues() {
        var params = new LinkedHashMap<String, Object>();
        params.put("ID", 9100000001L);
        params.put("NAME", "O'Hara");
        params.put("DOB", LocalDateTime.of(2020, 5, 1, 8, 30));
        params.put("MID", null);
        assertThat(params.values().stream().map(MockTables::literal).toList())
                .containsExactly("9100000001", "'O''Hara'", "TIMESTAMP '2020-05-01 08:30:00'", "NULL");
    }
}
