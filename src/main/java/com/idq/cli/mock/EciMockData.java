package com.idq.cli.mock;

import static com.idq.cli.core.EntityBuilder.entity;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EntityBuilder;
import com.idq.cli.source.eci.EciSources.DChild;
import com.idq.cli.source.eci.EciSources.DFamily;
import com.idq.cli.source.eci.EciSources.DMedicaid;
import com.idq.cli.source.eci.EciSources.EtlSrcFamilyAddress;
import com.idq.cli.source.eci.EciSources.EtlSrcFamilyPhone;
import com.idq.cli.source.eci.EciSources.SnCase;
import com.idq.cli.source.eci.EciSources.SnChild;
import java.math.BigDecimal;
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

    /// Every fourth child has the dummy SSN `000123456`, child 2 no first name, every fifth an unknown language.
    private void childrenAndFamilies() {
        tables.deleteRange("STG_ECI_D_CHILD", "ID_CHILD", ID, ID + 999_999);
        tables.deleteRange("STG_ECI_D_FAMILY", "ID_FAMILY", ID, ID + 999_999);
        tables.deleteRange("STG_ECI_SN_CHILD", "ID_CHILD", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            var gender = faker.options().option("M", "F");
            tables.insert(entity(DChild.class)
                    .with(DChild::idChild, id)
                    .with(DChild::childSsn, i % 4 == 0 ? "000123456" : "%09d".formatted(123_450_000 + i))
                    .with(DChild::firstName, i == 2 ? null : tables.text(faker.name().firstName()))
                    .with(DChild::lastName, tables.text(faker.name().lastName()))
                    .with(DChild::middleInitial, "A")
                    .with(DChild::dob, past(3))
                    .with(DChild::gender, gender)
                    .with(DChild::birthWtLb, 7)
                    .with(DChild::birthWtOz, 4)
                    .with(DChild::languageCd, i % 5 == 0 ? 99 : 1)
                    .with(DChild::ethnicity, 1)
                    .with(DChild::raceWhite, 1)
                    .with(DChild::raceAa, i % 3 == 0 ? 1 : 0)
                    .with(DChild::raceAsian, 0)
                    .with(DChild::racePi, 0)
                    .with(DChild::raceAn, 0)
                    .with(DChild::dateCreated, past(2))
                    .with(DChild::dateModified, past(1))
                    .with(DChild::createdBy, "mock")
                    .with(DChild::modifiedBy, "mock")
                    .with(DChild::loadDate, LocalDateTime.now()));
            tables.insert(entity(SnChild.class)
                    .with(SnChild::idChild, id)
                    .with(SnChild::gender, gender));
            tables.insert(entity(DFamily.class)
                    .with(DFamily::idFamily, id)
                    .with(DFamily::idChild, id)
                    .with(DFamily::familyCd, 1)
                    .with(DFamily::gender, "F")
                    .with(DFamily::firstName, tables.text(faker.name().firstName()))
                    .with(DFamily::lastName, tables.text(faker.name().lastName()))
                    .with(DFamily::dob, past(40))
                    .with(DFamily::dateCreated, past(2))
                    .with(DFamily::loadDate, LocalDateTime.now()));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Validation() {
        childrenAndFamilies();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty() {
        childrenAndFamilies();
    }

    /// Every sixth address has the unknown address code `9`.
    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Addr() {
        tables.deleteRange("V_ECI_ETL_SRC_FAMILY_ADDRESS", "ID", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            tables.insert(entity(EtlSrcFamilyAddress.class)
                    .with(EtlSrcFamilyAddress::sourceTable, i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD")
                    .with(EtlSrcFamilyAddress::id, BigDecimal.valueOf(id))
                    .with(EtlSrcFamilyAddress::idFamilyAddress, BigDecimal.valueOf(500 + i))
                    .with(EtlSrcFamilyAddress::address1, tables.text(faker.address().streetAddress()))
                    .with(EtlSrcFamilyAddress::address2, i % 3 == 0 ? tables.text("Suite 4") : null)
                    .with(EtlSrcFamilyAddress::addressCd, BigDecimal.valueOf(i % 6 == 0 ? 9 : 1))
                    .with(EtlSrcFamilyAddress::cityName, tables.text("Austin"))
                    .with(EtlSrcFamilyAddress::countyName, tables.text("Travis"))
                    .with(EtlSrcFamilyAddress::stateAbbrev, "TX")
                    .with(EtlSrcFamilyAddress::zipCode, "78701")
                    .with(EtlSrcFamilyAddress::zipSfx, "1234")
                    .with(EtlSrcFamilyAddress::lastUpdateDate, past(1)));
        }
    }

    /// Every fourth Medicaid number is malformed (`12-34`).
    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id() {
        childrenAndFamilies();
        tables.deleteRange("STG_ECI_D_MEDICAID", "ID_CASE", ID, ID + 999_999);
        tables.deleteRange("STG_ECI_SN_CASE", "ID_CASE", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            tables.insert(entity(SnCase.class)
                    .with(SnCase::idCase, id)
                    .with(SnCase::idChild, id));
            tables.insert(entity(DMedicaid.class)
                    .with(DMedicaid::idMedicaid, 800L + i)
                    .with(DMedicaid::idCase, id)
                    .with(DMedicaid::medicaidNbr, i % 4 == 0 ? "12-34" : "%09d".formatted(512_000_000 + i))
                    .with(DMedicaid::dateCreated, past(2))
                    .with(DMedicaid::dateModified, past(1)));
        }
    }

    /// One phone and one e-mail per party; every fourth phone has no area code, every fifth e-mail is broken.
    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr() {
        tables.execute("DELETE FROM V_ECI_ETL_SRC_FAMILY_PHONE WHERE ID LIKE '9100000___'", Map.of());
        for (var id : ids()) {
            int i = (int) (id - ID);
            var periodStart = past(1);
            tables.insert(contact(id, i, periodStart)
                    .with(EtlSrcFamilyPhone::idFamilyPhone, "P" + i)
                    .with(EtlSrcFamilyPhone::phoneEmailType, "PHONE")
                    .with(EtlSrcFamilyPhone::phoneEmail, i % 4 == 0 ? "5551234" : "512555%04d".formatted(i))
                    .with(EtlSrcFamilyPhone::phoneTp, "Telephone")
                    .with(EtlSrcFamilyPhone::usgTp, "001")
                    .with(EtlSrcFamilyPhone::prefLvl, "Primary"));
            tables.insert(contact(id, i, periodStart)
                    .with(EtlSrcFamilyPhone::idFamilyPhone, "E" + i)
                    .with(EtlSrcFamilyPhone::phoneEmailType, "EADDRESS")
                    .with(EtlSrcFamilyPhone::phoneEmail,
                            tables.text(i % 5 == 0 ? "broken@" : faker.internet().emailAddress())));
        }
    }

    private static EntityBuilder<EtlSrcFamilyPhone> contact(long id, int i, LocalDateTime periodStart) {
        return entity(EtlSrcFamilyPhone.class)
                .with(EtlSrcFamilyPhone::sourceTable, i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD")
                .with(EtlSrcFamilyPhone::id, String.valueOf(id))
                .with(EtlSrcFamilyPhone::idCase, BigDecimal.valueOf(id))
                .with(EtlSrcFamilyPhone::periodStartDate, periodStart);
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Rel() {
        childrenAndFamilies();
    }
}
