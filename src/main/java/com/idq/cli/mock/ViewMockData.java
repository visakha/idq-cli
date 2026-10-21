package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.models.FssSources.EtlSrcRelations;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import com.idq.cli.source.wic.etldb.models.WicSources;
import java.math.BigDecimal;
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

    /// Every third client is a registration, client 2 has no first name, every fourth an unknown suffix; every
    /// even client is related to the previous one as child and mother.
    void fss() {
        tables.deleteRange("V_FSS_ETL_SRC", "ID_CLIENT", ID, ID + 999_999);
        tables.deleteRange("V_FSS_ETL_SRC_RELATIONS", "ID_CLIENT", ID, ID + 999_999);
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert(FssSources.EtlSrc.builder()
                    .sourceType(i % 3 == 0 ? "REGIST" : "CLIENT")
                    .dtCreated(past(3))
                    .dtLastUpdate(past(1))
                    .stgUpdateDate(LocalDateTime.now())
                    .idClient(id)
                    .ptySrcKey(key(id))
                    .nmFirst(i == 2 ? null : tables.text(faker.name().firstName()))
                    .nmLast(tables.text(faker.name().lastName()))
                    .cdSuffix(i % 4 == 0 ? "XX" : "JR")
                    .dtDob(past(30))
                    .cdGender(faker.options().option("M", "F"))
                    .languageCd("ENG")
                    .cdHispanic("H")
                    .raceWhite(BigDecimal.ONE)
                    .raceAa(BigDecimal.ZERO)
                    .raceAsian(BigDecimal.ZERO)
                    .racePi(BigDecimal.ZERO)
                    .raceAn(BigDecimal.ZERO)
                    .addrLine1(tables.text(faker.address().streetAddress()))
                    .addrCity(tables.text("Austin"))
                    .addrState("TX")
                    .addrZip("78701")
                    .cdCnty("227")
                    .nbrPhone("512555%04d".formatted(i))
                    .nbrPhoneExt(i % 5 == 0 ? "1" : null)
                    .addrEmail(tables.text(faker.internet().emailAddress()))
                    .dtlCapxaction("I")
                    .clientDtlCapxaction("I")
                    .idRegistrationClient(600L + i)
                    .idRegistration(700L + i)
                    .lastActiveClientRegistrationYn("Y")
                    .lastInactvClientYn("N")
                    .build());
            if (i % 2 == 0) {
                for (var direction : new String[] {"To Child", "From Child"}) {
                    tables.insert(EtlSrcRelations.builder()
                            .relationDirection(direction)
                            .idClient(id)
                            .relnIdClient(id - 1)
                            .ptySrcKey(key(id))
                            .relnPtySrcKey(key(id - 1))
                            .cdGender("M")
                            .relnCdGender("F")
                            .cdReltshpToTc("MOTHER")
                            .relnDtCreated(past(2))
                            .relnDtLastUpdate(past(1))
                            .idRegistration(700L + i)
                            .build());
                }
            }
        });
    }

    /// Client 2 has the junk first name `DECLINED` (never prefixed), every fourth phone is too short.
    void ttf() {
        tables.deleteRange("V_TTF_ETL_SRC", "CLIENTS_ID", ID, ID + 999_999);
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert(TtfSources.EtlSrc.builder()
                    .clientsId(id)
                    .ptySrcKey(key(id))
                    .firstname(i == 2 ? "DECLINED" : tables.text(faker.name().firstName()))
                    .lastname(tables.text(faker.name().lastName()))
                    .dob(past(30))
                    .sexid(i % 2 == 0 ? 33 : 34)
                    .raceethnicityid(i % 3 == 0 ? "55" : "W")
                    .phone(i % 4 == 0 ? "123" : "214555%04d".formatted(i))
                    .submitdate(past(1))
                    .createddate(past(2))
                    .loadDate(LocalDateTime.now())
                    .clientExistsFlag("Y")
                    .build());
        });
    }

    /// Alternating family and client rows; client 3 has no last name.
    void wic() {
        tables.execute("DELETE FROM V_WIC_ETL_SRC WHERE ID LIKE '9100000___'", Map.of());
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert(WicSources.EtlSrc.builder()
                    .sourceTable(i % 2 == 0 ? "FAMILY" : "CLIENT")
                    .datekey(past(1))
                    .loadDate(LocalDateTime.now())
                    .id(String.valueOf(id))
                    .ptySrcKey(key(id))
                    .fid(String.valueOf(400 + i))
                    .firstName(tables.text(faker.name().firstName()))
                    .lastName(i == 3 ? null : tables.text(faker.name().lastName()))
                    .dob(past(5))
                    .gender(faker.options().option("M", "F", "U"))
                    .birthWtLb(BigDecimal.valueOf(6))
                    .birthWtOz(BigDecimal.valueOf(11))
                    .languageCd("ENG")
                    .ethnicity("H")
                    .raceWhiteInd(BigDecimal.ONE)
                    .raceAaInd(BigDecimal.ZERO)
                    .raceAsianInd(BigDecimal.ZERO)
                    .racePiInd(BigDecimal.ZERO)
                    .raceAnInd(BigDecimal.ZERO)
                    .address1(tables.text(faker.address().streetAddress()))
                    .city(tables.text("Houston"))
                    .zipCode("77002")
                    .county(tables.text("Harris"))
                    .phone("713555%04d".formatted(i))
                    .email(tables.text(faker.internet().emailAddress()))
                    .dateAddressValidFrom(past(2))
                    .build());
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
