package com.idq.cli.mock;

import static com.idq.cli.mock.MockTables.row;

import com.idq.cli.config.EtlSettings;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.stream.LongStream;
import net.datafaker.Faker;
import org.springframework.stereotype.Component;

/// Mock ECI source rows: children `9100000001...`, family members with the same ids (one parent per child).
@Component
public class EciMockData {

    static final long ID = 9_100_000_000L;

    private final MockTables tables;
    private final EtlSettings settings;
    private final Faker faker = new Faker(new Random(7));

    public EciMockData(MockTables tables, EtlSettings settings) {
        this.tables = tables;
        this.settings = settings;
    }

    List<Long> ids() {
        return LongStream.rangeClosed(1, settings.mockRowsPerTable()).map(i -> ID + i).boxed().toList();
    }

    private LocalDateTime past(int years) {
        return LocalDateTime.now().minusDays(faker.number().numberBetween(30, 365L * years)).withNano(0);
    }

    private void childrenAndFamilies() {
        tables.deleteRange("STG_ECI_D_CHILD", "ID_CHILD", ID, ID + 999_999);
        tables.deleteRange("STG_ECI_D_FAMILY", "ID_FAMILY", ID, ID + 999_999);
        tables.deleteRange("STG_ECI_SN_CHILD", "ID_CHILD", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            var gender = faker.options().option("M", "F");
            tables.insert("STG_ECI_D_CHILD", row("ID_CHILD", id, "CHILD_SSN", i % 4 == 0 ? "000123456"
                    : "%09d".formatted(123_450_000 + i), "FIRST_NAME", i == 2 ? null : faker.name().firstName(),
                    "LAST_NAME", faker.name().lastName(), "MIDDLE_INITIAL", "A", "DOB", past(3), "GENDER", gender,
                    "BIRTH_WT_LB", 7, "BIRTH_WT_OZ", 4, "LANGUAGE_CD", i % 5 == 0 ? "99" : "1", "ETHNICITY", 1,
                    "RACE_WHITE", 1, "RACE_AA", i % 3 == 0 ? 1 : 0, "RACE_ASIAN", 0, "RACE_PI", 0, "RACE_AN", 0,
                    "DATE_CREATED", past(2), "DATE_MODIFIED", past(1), "CREATED_BY", "mock", "MODIFIED_BY", "mock",
                    "LOAD_DATE", LocalDateTime.now()));
            tables.insert("STG_ECI_SN_CHILD", row("ID_CHILD", id, "GENDER", gender));
            tables.insert("STG_ECI_D_FAMILY", row("ID_FAMILY", id, "ID_CHILD", id, "FAMILY_CD", 1, "GENDER", "F",
                    "FIRST_NAME", faker.name().firstName(), "LAST_NAME", faker.name().lastName(), "MIDDLE_INITIAL",
                    null, "DOB", past(40), "DATE_CREATED", past(2), "DATE_MODIFIED", null, "LOAD_DATE",
                    LocalDateTime.now()));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Validation() {
        childrenAndFamilies();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty() {
        childrenAndFamilies();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Addr() {
        tables.deleteRange("V_ECI_ETL_SRC_FAMILY_ADDRESS", "ID", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            tables.insert("V_ECI_ETL_SRC_FAMILY_ADDRESS", row("SOURCE_TABLE", i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD",
                    "ID", id, "ID_FAMILY_ADDRESS", 500 + i, "ADDRESS1", faker.address().streetAddress(), "ADDRESS2",
                    i % 3 == 0 ? "Suite 4" : null, "ADDRESS_CD", i % 6 == 0 ? 9 : 1, "CITY_NAME", "Austin",
                    "COUNTY_NAME", "Travis", "STATE_ABBREV", "TX", "ZIP_CODE", "78701", "ZIP_SFX", "1234",
                    "LAST_UPDATE_DATE", past(1)));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id() {
        childrenAndFamilies();
        tables.deleteRange("STG_ECI_D_MEDICAID", "ID_CASE", ID, ID + 999_999);
        tables.deleteRange("STG_ECI_SN_CASE", "ID_CASE", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            tables.insert("STG_ECI_SN_CASE", row("ID_CASE", id, "ID_CHILD", id));
            tables.insert("STG_ECI_D_MEDICAID", row("ID_MEDICAID", 800 + i, "ID_CHILD", id, "ID_CASE", id,
                    "MEDICAID_NBR", i % 4 == 0 ? "12-34" : "%09d".formatted(512_000_000 + i), "DATE_CREATED",
                    past(2), "DATE_MODIFIED", past(1)));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr() {
        tables.execute("DELETE FROM V_ECI_ETL_SRC_FAMILY_PHONE WHERE ID LIKE '9100000___'", Map.of());
        for (var id : ids()) {
            int i = (int) (id - ID);
            var common = row("SOURCE_TABLE", i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD", "ID", String.valueOf(id),
                    "ID_CASE", id, "PERIOD_START_DATE", past(1));
            var phone = new java.util.HashMap<>(common);
            phone.putAll(row("ID_FAMILY_PHONE", "P" + i, "PHONE_EMAIL_TYPE", "PHONE", "PHONE_EMAIL",
                    i % 4 == 0 ? "5551234" : "512555%04d".formatted(i), "PHONE_TP", "Telephone", "USG_TP", "001",
                    "PREF_LVL", "Primary"));
            tables.insert("V_ECI_ETL_SRC_FAMILY_PHONE", phone);
            var email = new java.util.HashMap<>(common);
            email.putAll(row("ID_FAMILY_PHONE", "E" + i, "PHONE_EMAIL_TYPE", "EADDRESS", "PHONE_EMAIL",
                    i % 5 == 0 ? "broken@" : faker.internet().emailAddress()));
            tables.insert("V_ECI_ETL_SRC_FAMILY_PHONE", email);
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Rel() {
        childrenAndFamilies();
    }
}
