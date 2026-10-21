package com.idq.cli.mock;

import static com.idq.cli.core.EntityBuilder.entity;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EntityBuilder;
import com.idq.cli.source.eci.etldb.models.EciSources.ChildDelta;
import com.idq.cli.source.eci.etldb.models.EciSources.FamilyDelta;
import com.idq.cli.source.eci.etldb.models.EciSources.MedicaidDelta;
import com.idq.cli.source.eci.etldb.models.EciSources.EtlSrcFamilyAddress;
import com.idq.cli.source.eci.etldb.models.EciSources.EtlSrcFamilyPhone;
import com.idq.cli.source.eci.etldb.models.EciSources.SnCase;
import com.idq.cli.source.eci.etldb.models.EciSources.SnChild;
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
            tables.insert(entity(ChildDelta.class)
                    .with(ChildDelta::idChild, id)
                    .with(ChildDelta::childSsn, i % 4 == 0 ? "000123456" : "%09d".formatted(123_450_000 + i))
                    .with(ChildDelta::firstName, i == 2 ? null : tables.text(faker.name().firstName()))
                    .with(ChildDelta::lastName, tables.text(faker.name().lastName()))
                    .with(ChildDelta::middleInitial, "A")
                    .with(ChildDelta::dob, past(3))
                    .with(ChildDelta::gender, gender)
                    .with(ChildDelta::birthWtLb, 7)
                    .with(ChildDelta::birthWtOz, 4)
                    .with(ChildDelta::languageCd, i % 5 == 0 ? 99 : 1)
                    .with(ChildDelta::ethnicity, 1)
                    .with(ChildDelta::raceWhite, 1)
                    .with(ChildDelta::raceAa, i % 3 == 0 ? 1 : 0)
                    .with(ChildDelta::raceAsian, 0)
                    .with(ChildDelta::racePi, 0)
                    .with(ChildDelta::raceAn, 0)
                    .with(ChildDelta::dateCreated, past(2))
                    .with(ChildDelta::dateModified, past(1))
                    .with(ChildDelta::createdBy, "mock")
                    .with(ChildDelta::modifiedBy, "mock")
                    .with(ChildDelta::loadDate, LocalDateTime.now()));
            tables.insert(SnChild.builder()
                    .idChild(id)
                    .gender(gender)
                    .build());
            tables.insert(FamilyDelta.builder()
                    .idFamily(id)
                    .idChild(id)
                    .familyCd(1)
                    .gender("F")
                    .firstName(tables.text(faker.name().firstName()))
                    .lastName(tables.text(faker.name().lastName()))
                    .dob(past(40))
                    .dateCreated(past(2))
                    .loadDate(LocalDateTime.now())
                    .build());
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
            tables.insert(entity(MedicaidDelta.class)
                    .with(MedicaidDelta::idMedicaid, 800L + i)
                    .with(MedicaidDelta::idCase, id)
                    .with(MedicaidDelta::medicaidNbr, i % 4 == 0 ? "12-34" : "%09d".formatted(512_000_000 + i))
                    .with(MedicaidDelta::dateCreated, past(2))
                    .with(MedicaidDelta::dateModified, past(1)));
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
