package com.idq.cli.mock;

import static com.idq.cli.mock.MockTables.row;
import static com.idq.cli.mock.MockTables.text;

import com.idq.cli.config.EtlSettings;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Random;
import java.util.stream.IntStream;
import net.datafaker.Faker;
import org.springframework.stereotype.Component;

/// Mock rows for the FSS, TTF and WIC source views (`V_FSS_ETL_SRC`, `V_FSS_ETL_SRC_RELATIONS`, `V_TTF_ETL_SRC`,
/// `V_WIC_ETL_SRC`). Every mapping of those workflows reads one view, so the mapping fill functions share them.
@Component
public class ViewMockData {

    static final long ID = 9_100_000_000L;

    private final MockTables tables;
    private final EtlSettings settings;
    private final Faker faker = new Faker(new Random(11));

    public ViewMockData(MockTables tables, EtlSettings settings) {
        this.tables = tables;
        this.settings = settings;
    }

    private IntStream rows() {
        return IntStream.rangeClosed(1, settings.mockRowsPerTable());
    }

    private LocalDateTime past(int years) {
        return LocalDateTime.now().minusDays(faker.number().numberBetween(30, 365L * years)).withNano(0);
    }

    private static String key(long id) {
        return String.valueOf(id).substring(String.valueOf(id).length() - 10);
    }

    void fss() {
        tables.deleteRange("V_FSS_ETL_SRC", "ID_CLIENT", ID, ID + 999_999);
        tables.deleteRange("V_FSS_ETL_SRC_RELATIONS", "ID_CLIENT", ID, ID + 999_999);
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert("V_FSS_ETL_SRC", row("SOURCE_TYPE", i % 3 == 0 ? "REGIST" : "CLIENT", "DT_CREATED",
                    past(3), "DT_LAST_UPDATE", past(1), "STG_UPDATE_DATE", LocalDateTime.now(), "ID_CLIENT", id,
                    "PTY_SRC_KEY", key(id), "NM_FIRST", i == 2 ? null : text(faker.name().firstName()), "NM_LAST",
                    text(faker.name().lastName()), "NM_MIDDLE", null, "CD_SUFFIX", i % 4 == 0 ? "XX" : "JR", "DT_DOB",
                    past(30), "CD_GENDER", faker.options().option("M", "F"), "LANGUAGE_CD", "ENG", "CD_HISPANIC",
                    "H", "RACE_WHITE", 1, "RACE_AA", 0, "RACE_ASIAN", 0, "RACE_PI", 0, "RACE_AN", 0, "ADDR_LINE1",
                    text(faker.address().streetAddress()), "ADDR_CITY", text("Austin"), "ADDR_STATE", "TX",
                    "ADDR_ZIP", "78701", "CD_CNTY", "227", "NBR_PHONE", "512555%04d".formatted(i),
                    "NBR_PHONE_EXT", i % 5 == 0 ? "1" : null,
                    "ADDR_EMAIL", text(faker.internet().emailAddress()), "DTL__CAPXACTION", "I",
                    "CLIENT_DTL__CAPXACTION", "I", "ID_REGISTRATION_CLIENT", 600 + i, "ID_REGISTRATION", 700 + i,
                    "LAST_ACTIVE_CLIENT_REGISTRATION_YN", "Y", "LAST_INACTV_CLIENT_YN", "N"));
            if (i % 2 == 0) {
                for (var direction : new String[] {"To Child", "From Child"}) {
                    tables.insert("V_FSS_ETL_SRC_RELATIONS", row("RELATION_DIRECTION", direction, "ID_CLIENT", id,
                            "RELN_ID_CLIENT", id - 1, "PTY_SRC_KEY", key(id), "RELN_PTY_SRC_KEY", key(id - 1),
                            "CD_GENDER", "M", "RELN_CD_GENDER", "F", "CD_RELTSHP_TO_TC", "MOTHER",
                            "RELN_DT_CREATED", past(2), "RELN_DT_LAST_UPDATE", past(1), "ID_REGISTRATION", 700 + i));
                }
            }
        });
    }

    void ttf() {
        tables.deleteRange("V_TTF_ETL_SRC", "CLIENTS_ID", ID, ID + 999_999);
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert("V_TTF_ETL_SRC", row("CLIENTS_ID", id, "PTY_SRC_KEY", key(id), "FIRSTNAME",
                    i == 2 ? "DECLINED" : text(faker.name().firstName()), "LASTNAME", text(faker.name().lastName()),
                    "MIDDLENAME", null, "DOB", past(30), "SEXID", i % 2 == 0 ? 33 : 34,
                    "RACEETHNICITYID", i % 3 == 0 ? "55" : "W",
                    "PHONE", i % 4 == 0 ? "123" : "214555%04d".formatted(i), "SUBMITDATE", past(1), "CREATEDDATE",
                    past(2), "LOAD_DATE", LocalDateTime.now(), "CLIENT_EXISTS_FLAG", "Y"));
        });
    }

    void wic() {
        tables.execute("DELETE FROM V_WIC_ETL_SRC WHERE ID LIKE '9100000___'", Map.of());
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert("V_WIC_ETL_SRC", row("SOURCE_TABLE", i % 2 == 0 ? "FAMILY" : "CLIENT", "DATEKEY", past(1),
                    "LOAD_DATE", LocalDateTime.now(), "ID", String.valueOf(id), "PTY_SRC_KEY", key(id), "FID",
                    String.valueOf(400 + i), "FIRST_NAME", text(faker.name().firstName()), "LAST_NAME",
                    i == 3 ? null : text(faker.name().lastName()), "MIDDLE_NAME", null, "DOB", past(5), "GENDER",
                    faker.options().option("M", "F", "U"), "BIRTH_WT_LB", 6, "BIRTH_WT_OZ", 11, "LANGUAGE_CD", "ENG",
                    "ETHNICITY", "H", "RACE_WHITE_IND", 1, "RACE_AA_IND", 0, "RACE_ASIAN_IND", 0, "RACE_PI_IND", 0,
                    "RACE_AN_IND", 0, "ADDRESS1", text(faker.address().streetAddress()), "CITY", text("Houston"),
                    "ZIP_CODE", "77002", "COUNTY", text("Harris"), "PHONE", "713555%04d".formatted(i), "EMAIL",
                    text(faker.internet().emailAddress()), "DATE_ADDRESS_VALID_FROM", past(2)));
        });
    }

    public void fill_sample_mock_data_m_Tgt_C_S_FSS_Pty_Validation() {
        fss();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_FSS_Pty() {
        fss();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_FSS_Pty_Addr() {
        fss();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id() {
        fss();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr() {
        fss();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_FSS_Pty_Rle_Rel() {
        fss();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TTF_Pty_Validation() {
        ttf();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TTF_Pty() {
        ttf();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id() {
        ttf();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TTF_Pty_Rle_Phn() {
        ttf();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_WIC_Pty_Validation() {
        wic();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_WIC_Pty() {
        wic();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_WIC_Pty_Addr() {
        wic();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id() {
        wic();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr() {
        wic();
    }
}
