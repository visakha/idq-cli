package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.source.cre.etldb.models.CreSources.CareCaseMaintDelta;
import com.idq.cli.source.cre.etldb.models.CreSources.CareClients;
import com.idq.cli.source.cre.etldb.models.CreSources.CareClientsDelta;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Random;
import java.util.stream.IntStream;
import net.datafaker.Faker;
import org.springframework.stereotype.Component;

/// Mock CRE source rows: CARE clients `9100000001...` in the delta and in the snapshot. Every fifth client is a
/// maintained case (`MAINT_FLAG` `D`): the tenth ones are deleted (`CASEDEL`), the others moved onto the previous
/// client (`CASEMOV`). Client 2 has no last name, client 3 lives abroad (state `FC`, which the mock reference data
/// translates to `99`), every fourth has an unknown suffix, every sixth the dummy SSN `U`, every seventh a short phone.
@Component
public class CreMockData {

    static final long ID = 9_100_000_000L;

    private final MockTables tables;
    private final EtlSettings settings;
    private final Faker faker = new Faker(new Random(13));

    public CreMockData(MockTables tables, EtlSettings settings) {
        this.tables = tables;
        this.settings = settings;
    }

    private IntStream rows() {
        return IntStream.rangeClosed(1, settings.mockRowsPerTable());
    }

    private LocalDateTime past(int years) {
        return LocalDateTime.now().minusDays(faker.number().numberBetween(30, 365L * years)).withNano(0);
    }

    /// Faker values longer than the CARE columns (first name 11, last name 16, street 25, city 20) are cut.
    private static String cut(String value, int length) {
        return value.length() <= length ? value : value.substring(0, length);
    }

    private static String careId(long i) {
        return String.valueOf(ID + i);
    }

    void cre() {
        tables.skipIf("STG_CRE_D_CARE_CLIENTS", "CARE_ID LIKE '9100000___'", Map.of());
        tables.skipIf("STG_CRE_SN_CARE_CLIENTS", "CARE_ID LIKE '9100000___'", Map.of());
        tables.skipIf("STG_CRE_D_CARE_CASE_MAINT", "SOURCE_ID LIKE '9100000___'", Map.of());
        rows().forEach(i -> {
            var lastUpdate = past(1);
            var first = tables.text(cut(faker.name().firstName(), 11));
            var last = i == 2 ? null : tables.text(cut(faker.name().lastName(), 16));
            var street = tables.text(cut(faker.address().streetAddress(), 25));
            var birth = past(40);
            var sex = i % 8 == 0 ? "X" : faker.options().option("M", "F");
            var maintained = i % 5 == 0;
            tables.insert(CareClientsDelta.builder()
                    .careId(careId(i))
                    .careLastupDt(lastUpdate)
                    .firstnm(first)
                    .lastnm(last)
                    .lastSuf(i % 4 == 0 ? "XX" : "JR")
                    .birthDt(birth)
                    .sex(sex)
                    .street(street)
                    .city(tables.text("Austin"))
                    .cnty("227")
                    .state(i == 3 ? "FC" : "TX")
                    .zip("78701")
                    .zipsuf("1234")
                    .phone(i % 7 == 0 ? "555" : "512555%04d".formatted(i))
                    .recipNo("5%08d".formatted(i))
                    .maintFlag(maintained ? "D" : null)
                    .ssn(i % 6 == 0 ? "U" : "%09d".formatted(123_450_000 + i))
                    .insertDate(LocalDateTime.now().withNano(0))
                    .fedeth("H")
                    .race("W")
                    .extractDt(LocalDateTime.now().withNano(0))
                    .build());
            tables.insert(CareClients.builder()
                    .careId(careId(i))
                    .careLastupDt(lastUpdate)
                    .firstnm(first)
                    .lastnm(last)
                    .lastSuf("JR")
                    .birthDt(birth)
                    .sex(sex)
                    .street(street)
                    .city(tables.text("Austin"))
                    .cnty("227")
                    .state("TX")
                    .zip("78701")
                    .zipsuf("1234")
                    .phone("512555%04d".formatted(i))
                    .recipNo("5%08d".formatted(i))
                    .ssn("%09d".formatted(123_450_000 + i))
                    .insertDate(past(3))
                    .fedeth("H")
                    .race("W")
                    .extractDt(LocalDateTime.now().withNano(0))
                    .build());
            if (maintained) {
                boolean deleted = i % 10 == 0;
                tables.insert(CareCaseMaintDelta.builder()
                        .addDt(LocalDateTime.now().withNano(0))
                        .addTm("0800")
                        .rec(deleted ? "CASEDEL" : "CASEMOV")
                        .comp("CRE")
                        .sourceCase("C" + careId(i))
                        .targetCase(deleted ? null : "C" + careId(i - 1))
                        .sourceId(careId(i))
                        .targetId(deleted ? null : careId(i - 1))
                        .extractDt(LocalDateTime.now().withNano(0))
                        .insertDate(LocalDateTime.now().withNano(0))
                        .build());
            }
        });
    }

    public void fill_sample_mock_data_m_Tgt_C_S_CRE_CARE_Clients() {
        cre();
    }
}
