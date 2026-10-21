package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
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

    /// Every fourth child has the dummy SSN `000123456`, child 2 a blank first name (a space: the `ADMIN` schema's
    /// `FIRST_NAME` is `NOT NULL`, and Oracle stores `''` as `NULL`), every fifth an unknown language.
    private void childrenAndFamilies() {
        tables.skipIfPresent("STG_ECI_D_CHILD", "ID_CHILD", ID, ID + 999_999);
        tables.skipIfPresent("STG_ECI_D_FAMILY", "ID_FAMILY", ID, ID + 999_999);
        tables.skipIfPresent("STG_ECI_SN_CHILD", "ID_CHILD", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            var gender = faker.options().option("M", "F");
            tables.insert(ChildDelta.builder()
                    .idChild(id)
                    .childSsn(i % 4 == 0 ? "000123456" : "%09d".formatted(123_450_000 + i))
                    .firstName(i == 2 ? " " : tables.text(faker.name().firstName()))
                    .lastName(tables.text(faker.name().lastName()))
                    .middleInitial("A")
                    .dob(past(3))
                    .gender(gender)
                    .birthWtLb(7)
                    .birthWtOz(4)
                    .languageCd(i % 5 == 0 ? 99 : 1)
                    .ethnicity(1)
                    .raceWhite(1)
                    .raceAa(i % 3 == 0 ? 1 : 0)
                    .raceAsian(0)
                    .racePi(0)
                    .raceAn(0)
                    .dateCreated(past(2))
                    .dateModified(past(1))
                    .createdBy("mock")
                    .modifiedBy("mock")
                    .loadDate(LocalDateTime.now())
                    .build());
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
        tables.skipIfPresent("V_ECI_ETL_SRC_FAMILY_ADDRESS", "ID", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            tables.insert(EtlSrcFamilyAddress.builder()
                    .sourceTable(i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD")
                    .id(BigDecimal.valueOf(id))
                    .idFamilyAddress(BigDecimal.valueOf(500 + i))
                    .address1(tables.text(faker.address().streetAddress()))
                    .address2(i % 3 == 0 ? tables.text("Suite 4") : null)
                    .addressCd(BigDecimal.valueOf(i % 6 == 0 ? 9 : 1))
                    .cityName(tables.text("Austin"))
                    .countyName(tables.text("Travis"))
                    .stateAbbrev("TX")
                    .zipCode("78701")
                    .zipSfx("1234")
                    .lastUpdateDate(past(1))
                    .build());
        }
    }

    /// Every fourth Medicaid number is malformed (`12-34`).
    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id() {
        childrenAndFamilies();
        tables.skipIfPresent("STG_ECI_D_MEDICAID", "ID_CASE", ID, ID + 999_999);
        tables.skipIfPresent("STG_ECI_SN_CASE", "ID_CASE", ID, ID + 999_999);
        for (var id : ids()) {
            int i = (int) (id - ID);
            tables.insert(SnCase.builder()
                    .idCase(id)
                    .idChild(id)
                    .build());
            tables.insert(MedicaidDelta.builder()
                    .idMedicaid(800L + i)
                    .idCase(id)
                    .medicaidNbr(i % 4 == 0 ? "12-34" : "%09d".formatted(512_000_000 + i))
                    .eligDate(past(2))
                    .dateCreated(past(2))
                    .dateModified(past(1))
                    .loadDate(LocalDateTime.now())
                    .build());
        }
    }

    /// One phone and one e-mail per party; every fourth phone has no area code, every fifth e-mail is broken.
    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr() {
        tables.skipIf("V_ECI_ETL_SRC_FAMILY_PHONE", "ID LIKE '9100000___'", Map.of());
        for (var id : ids()) {
            int i = (int) (id - ID);
            var periodStart = past(1);
            tables.insert(contact(id, i, periodStart)
                    .idFamilyPhone("P" + i)
                    .phoneEmailType("PHONE")
                    .phoneEmail(i % 4 == 0 ? "5551234" : "512555%04d".formatted(i))
                    .phoneTp("Telephone")
                    .usgTp("001")
                    .prefLvl("Primary")
                    .build());
            tables.insert(contact(id, i, periodStart)
                    .idFamilyPhone("E" + i)
                    .phoneEmailType("EADDRESS")
                    .phoneEmail(tables.text(i % 5 == 0 ? "broken@" : faker.internet().emailAddress()))
                    .build());
        }
    }

    private static EtlSrcFamilyPhone.Builder contact(long id, int i, LocalDateTime periodStart) {
        return EtlSrcFamilyPhone.builder()
                .sourceTable(i % 2 == 0 ? "ECI_FAMILY" : "ECI_CHILD")
                .id(String.valueOf(id))
                .idCase(BigDecimal.valueOf(id))
                .periodStartDate(periodStart);
    }

    public void fill_sample_mock_data_m_Tgt_C_S_ECI_Pty_Rle_Rel() {
        childrenAndFamilies();
    }
}
