package com.idq.cli.mock;

import static com.idq.cli.core.EntityBuilder.entity;

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
            tables.insert(entity(FssSources.EtlSrc.class)
                    .with(FssSources.EtlSrc::sourceType, i % 3 == 0 ? "REGIST" : "CLIENT")
                    .with(FssSources.EtlSrc::dtCreated, past(3))
                    .with(FssSources.EtlSrc::dtLastUpdate, past(1))
                    .with(FssSources.EtlSrc::stgUpdateDate, LocalDateTime.now())
                    .with(FssSources.EtlSrc::idClient, id)
                    .with(FssSources.EtlSrc::ptySrcKey, key(id))
                    .with(FssSources.EtlSrc::nmFirst, i == 2 ? null : tables.text(faker.name().firstName()))
                    .with(FssSources.EtlSrc::nmLast, tables.text(faker.name().lastName()))
                    .with(FssSources.EtlSrc::cdSuffix, i % 4 == 0 ? "XX" : "JR")
                    .with(FssSources.EtlSrc::dtDob, past(30))
                    .with(FssSources.EtlSrc::cdGender, faker.options().option("M", "F"))
                    .with(FssSources.EtlSrc::languageCd, "ENG")
                    .with(FssSources.EtlSrc::cdHispanic, "H")
                    .with(FssSources.EtlSrc::raceWhite, BigDecimal.ONE)
                    .with(FssSources.EtlSrc::raceAa, BigDecimal.ZERO)
                    .with(FssSources.EtlSrc::raceAsian, BigDecimal.ZERO)
                    .with(FssSources.EtlSrc::racePi, BigDecimal.ZERO)
                    .with(FssSources.EtlSrc::raceAn, BigDecimal.ZERO)
                    .with(FssSources.EtlSrc::addrLine1, tables.text(faker.address().streetAddress()))
                    .with(FssSources.EtlSrc::addrCity, tables.text("Austin"))
                    .with(FssSources.EtlSrc::addrState, "TX")
                    .with(FssSources.EtlSrc::addrZip, "78701")
                    .with(FssSources.EtlSrc::cdCnty, "227")
                    .with(FssSources.EtlSrc::nbrPhone, "512555%04d".formatted(i))
                    .with(FssSources.EtlSrc::nbrPhoneExt, i % 5 == 0 ? "1" : null)
                    .with(FssSources.EtlSrc::addrEmail, tables.text(faker.internet().emailAddress()))
                    .with(FssSources.EtlSrc::dtlCapxaction, "I")
                    .with(FssSources.EtlSrc::clientDtlCapxaction, "I")
                    .with(FssSources.EtlSrc::idRegistrationClient, 600L + i)
                    .with(FssSources.EtlSrc::idRegistration, 700L + i)
                    .with(FssSources.EtlSrc::lastActiveClientRegistrationYn, "Y")
                    .with(FssSources.EtlSrc::lastInactvClientYn, "N"));
            if (i % 2 == 0) {
                for (var direction : new String[] {"To Child", "From Child"}) {
                    tables.insert(entity(EtlSrcRelations.class)
                            .with(EtlSrcRelations::relationDirection, direction)
                            .with(EtlSrcRelations::idClient, id)
                            .with(EtlSrcRelations::relnIdClient, id - 1)
                            .with(EtlSrcRelations::ptySrcKey, key(id))
                            .with(EtlSrcRelations::relnPtySrcKey, key(id - 1))
                            .with(EtlSrcRelations::cdGender, "M")
                            .with(EtlSrcRelations::relnCdGender, "F")
                            .with(EtlSrcRelations::cdReltshpToTc, "MOTHER")
                            .with(EtlSrcRelations::relnDtCreated, past(2))
                            .with(EtlSrcRelations::relnDtLastUpdate, past(1))
                            .with(EtlSrcRelations::idRegistration, 700L + i));
                }
            }
        });
    }

    /// Client 2 has the junk first name `DECLINED` (never prefixed), every fourth phone is too short.
    void ttf() {
        tables.deleteRange("V_TTF_ETL_SRC", "CLIENTS_ID", ID, ID + 999_999);
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert(entity(TtfSources.EtlSrc.class)
                    .with(TtfSources.EtlSrc::clientsId, id)
                    .with(TtfSources.EtlSrc::ptySrcKey, key(id))
                    .with(TtfSources.EtlSrc::firstname, i == 2 ? "DECLINED" : tables.text(faker.name().firstName()))
                    .with(TtfSources.EtlSrc::lastname, tables.text(faker.name().lastName()))
                    .with(TtfSources.EtlSrc::dob, past(30))
                    .with(TtfSources.EtlSrc::sexid, i % 2 == 0 ? 33 : 34)
                    .with(TtfSources.EtlSrc::raceethnicityid, i % 3 == 0 ? "55" : "W")
                    .with(TtfSources.EtlSrc::phone, i % 4 == 0 ? "123" : "214555%04d".formatted(i))
                    .with(TtfSources.EtlSrc::submitdate, past(1))
                    .with(TtfSources.EtlSrc::createddate, past(2))
                    .with(TtfSources.EtlSrc::loadDate, LocalDateTime.now())
                    .with(TtfSources.EtlSrc::clientExistsFlag, "Y"));
        });
    }

    /// Alternating family and client rows; client 3 has no last name.
    void wic() {
        tables.execute("DELETE FROM V_WIC_ETL_SRC WHERE ID LIKE '9100000___'", Map.of());
        rows().forEach(i -> {
            long id = ID + i;
            tables.insert(entity(WicSources.EtlSrc.class)
                    .with(WicSources.EtlSrc::sourceTable, i % 2 == 0 ? "FAMILY" : "CLIENT")
                    .with(WicSources.EtlSrc::datekey, past(1))
                    .with(WicSources.EtlSrc::loadDate, LocalDateTime.now())
                    .with(WicSources.EtlSrc::id, String.valueOf(id))
                    .with(WicSources.EtlSrc::ptySrcKey, key(id))
                    .with(WicSources.EtlSrc::fid, String.valueOf(400 + i))
                    .with(WicSources.EtlSrc::firstName, tables.text(faker.name().firstName()))
                    .with(WicSources.EtlSrc::lastName, i == 3 ? null : tables.text(faker.name().lastName()))
                    .with(WicSources.EtlSrc::dob, past(5))
                    .with(WicSources.EtlSrc::gender, faker.options().option("M", "F", "U"))
                    .with(WicSources.EtlSrc::birthWtLb, BigDecimal.valueOf(6))
                    .with(WicSources.EtlSrc::birthWtOz, BigDecimal.valueOf(11))
                    .with(WicSources.EtlSrc::languageCd, "ENG")
                    .with(WicSources.EtlSrc::ethnicity, "H")
                    .with(WicSources.EtlSrc::raceWhiteInd, BigDecimal.ONE)
                    .with(WicSources.EtlSrc::raceAaInd, BigDecimal.ZERO)
                    .with(WicSources.EtlSrc::raceAsianInd, BigDecimal.ZERO)
                    .with(WicSources.EtlSrc::racePiInd, BigDecimal.ZERO)
                    .with(WicSources.EtlSrc::raceAnInd, BigDecimal.ZERO)
                    .with(WicSources.EtlSrc::address1, tables.text(faker.address().streetAddress()))
                    .with(WicSources.EtlSrc::city, tables.text("Houston"))
                    .with(WicSources.EtlSrc::zipCode, "77002")
                    .with(WicSources.EtlSrc::county, tables.text("Harris"))
                    .with(WicSources.EtlSrc::phone, "713555%04d".formatted(i))
                    .with(WicSources.EtlSrc::email, tables.text(faker.internet().emailAddress()))
                    .with(WicSources.EtlSrc::dateAddressValidFrom, past(2)));
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
