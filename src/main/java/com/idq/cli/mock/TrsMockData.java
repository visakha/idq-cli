package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.MdmBaseTables.PartyRoleAltId;
import com.idq.cli.core.reference.MdmBaseTables.PartyRoleAltIdXref;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvDcMciAliasDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvDcMciIndvDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvEdMciEdgIndv;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvMciEdgIndvToaDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcAliasDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcCaseIndv;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcCases;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcCasesDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcIndvDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcIndvHist;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcPrimaryPayeeDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcRelationshipsDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.InManagedCareDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.IndvAddrDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.UniqueAddressDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.ValidMember;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Random;
import java.util.stream.Collectors;
import java.util.stream.LongStream;
import net.datafaker.Faker;
import org.springframework.stereotype.Component;

/// Mock TRS source rows (Datafaker). Individuals use ids `9100000001...`, cases `9200000001...`; every call first
/// removes the rows of those ranges, then generates fresh ones. A few rows are deliberately invalid (missing name,
/// future birth date, unknown codes) so that the exception paths are exercised.
@Component
public class TrsMockData {

    static final long INDV = 9_100_000_000L;
    static final long CASE = 9_200_000_000L;
    static final long EDG = 9_300_000_000L;

    private final MockTables tables;
    private final EtlSettings settings;
    private final Faker faker = new Faker(new Random(42));

    public TrsMockData(MockTables tables, EtlSettings settings) {
        this.tables = tables;
        this.settings = settings;
    }

    /// The demographics shared by the daily and the converted (MCI) individual tables.
    private record Person(BigDecimal indvId, String firstName, String midName, String lastName, String sufxName,
            String genderCd, String raceCd, LocalDateTime dob, LocalDateTime created, BigDecimal ssn) {}

    List<Long> individuals() {
        return LongStream.rangeClosed(1, settings.mockRowsPerTable()).map(i -> INDV + i).boxed().toList();
    }

    private static BigDecimal num(long value) {
        return BigDecimal.valueOf(value);
    }

    private void clean(String... indvTables) {
        for (var table : indvTables) {
            tables.deleteRange(table, "INDV_ID", INDV, INDV + 999_999);
        }
    }

    /// MCI key for every individual, daily (`|DC_INDV`) key for the even ones.
    private void validMembers() {
        clean("STG_TRS_VALID_MEMBERS");
        for (var id : individuals()) {
            validMember(id, String.valueOf(id), "MCI");
            if (id % 2 == 0) {
                validMember(id, id + "|DC_INDV", "DC_INDV");
            }
        }
    }

    private void validMember(long id, String ptyPk, String sourceTable) {
        tables.insert(ValidMember.builder()
                .indvId(id)
                .ptyPk(ptyPk)
                .srcTbl(sourceTable)
                .createDate(LocalDateTime.now())
                .build());
    }

    private LocalDateTime pastDate(int years) {
        return LocalDateTime.now().minusDays(faker.number().numberBetween(30, 365L * years)).withNano(0);
    }

    /// Individual 3 has no first name, 4 a birth date in the future; every 7th an unknown gender, every 6th race.
    private List<Person> people() {
        return individuals().stream().map(id -> {
            int i = (int) (id - INDV);
            return new Person(num(id), i == 3 ? null : tables.text(faker.name().firstName()),
                    tables.text(faker.name().firstName().substring(0, 1)), tables.text(faker.name().lastName()),
                    i % 5 == 0 ? "JR" : null, i % 7 == 0 ? "X" : faker.options().option("M", "F"),
                    i % 6 == 0 ? "Z" : "W", i == 4 ? LocalDateTime.now().plusYears(1) : pastDate(80), pastDate(2),
                    num(100_000_000L + faker.number().numberBetween(1, 665_000_000)));
        }).toList();
    }

    private List<DcIndvDelta> dailyIndividuals() {
        return people().stream().map(p -> tables.insert(DcIndvDelta.builder()
                .indvId(p.indvId())
                .historySeq(BigDecimal.ONE)
                .firstName(p.firstName())
                .midName(p.midName())
                .lastName(p.lastName())
                .sufxName(p.sufxName())
                .prefixName("MR")
                .genderCd(p.genderCd())
                .raceCd(p.raceCd())
                .ethnicityCd("H")
                .ssaValidationSw("Y")
                .fileClearanceSw("Y")
                .inactiveInd("N")
                .deleteSw("N")
                .dobDt(p.dob())
                .createDt(p.created())
                .ssn(p.ssn())
                .loadDate(LocalDateTime.now())
                .build())).toList();
    }

    private void convertedIndividuals() {
        people().forEach(p -> tables.insert(CvDcMciIndvDelta.builder()
                .indvId(p.indvId())
                .historySeq(BigDecimal.ONE)
                .firstName(p.firstName())
                .midName(p.midName())
                .lastName(p.lastName())
                .sufxName(p.sufxName())
                .prefixName("MR")
                .genderCd(p.genderCd())
                .raceCd(p.raceCd())
                .ethnicityCd("H")
                .inactiveInd("N")
                .dobDt(p.dob())
                .createDt(p.created())
                .ssn(p.ssn())
                .twConvertInd("Y")
                .ltcConvertInd("N")
                .build()));
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_OnGoing() {
        clean("STG_TRS_D_DC_INDV", "STG_TRS_D_CV_DC_MCI_INDV", "STG_TRS_D_CV_MCI_EDG_INDV_TOA");
        dailyIndividuals();
        convertedIndividuals();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing() {
        tables.deleteRange("STG_TRS_D_DC_PRIMARY_PAYEE", "CASE_NUM", CASE, CASE + 999_999);
        tables.deleteRange("STG_TRS_CV_ED_MCI_EDG_INDV", "CASE_NUM", CASE, CASE + 999_999);
        tables.deleteRange("STG_TRS_DC_CASES", "CASE_NUM", CASE, CASE + 999_999);
        validMembers();
        for (var id : individuals()) {
            var caseNum = num(CASE + (id - INDV));
            var edg = num(EDG + (id - INDV));
            tables.insert(DcPrimaryPayeeDelta.builder()
                    .caseNum(caseNum)
                    .edgNum(edg)
                    .addrTypeCd("MA")
                    .altPayeeExistsSw("Y")
                    .createDt(pastDate(1))
                    .build());
            tables.insert(CvEdMciEdgIndv.builder()
                    .caseNum(caseNum)
                    .edgNum(edg)
                    .indvId(num(id))
                    .eligEffBeginDt(pastDate(3))
                    .createDt(pastDate(1))
                    .build());
            tables.insert(DcCases.builder()
                    .caseNum(caseNum)
                    .authrepVerfCd("CS")
                    .sentAuthrepSw("Y")
                    .createDt(pastDate(1))
                    .build());
        }
    }

    /// Two aliases per individual; the second first name carries the junk suffix `0n`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Nm() {
        clean("STG_TRS_D_CV_DC_MCI_ALIAS", "STG_TRS_D_DC_ALIAS");
        validMembers();
        for (var id : individuals()) {
            for (int seq = 1; seq <= 2; seq++) {
                var firstName = tables.text(faker.name().firstName() + (seq == 2 ? "0n" : ""));
                var lastName = tables.text(faker.name().lastName());
                var created = pastDate(2);
                if (id % 2 == 0) {
                    tables.insert(DcAliasDelta.builder()
                            .indvId(num(id))
                            .seqNum(num(seq))
                            .firstName(firstName)
                            .lastName(lastName)
                            .createDt(created)
                            .build());
                } else {
                    tables.insert(CvDcMciAliasDelta.builder()
                            .indvId(num(id))
                            .sequenceNum(num(seq))
                            .firstName(firstName)
                            .lastName(lastName)
                            .createDt(created)
                            .build());
                }
            }
        }
    }

    /// The SSN history (`STG_TRS_H_DC_INDV`) repeats the SSN of every daily individual.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id() {
        clean("STG_TRS_D_DC_INDV", "STG_TRS_D_CV_DC_MCI_INDV", "STG_TRS_H_DC_INDV", "STG_TRS_D_CV_DC_MRG_SPRT_INDV");
        validMembers();
        var daily = dailyIndividuals();
        convertedIndividuals();
        daily.forEach(indv -> tables.insert(DcIndvHist.builder()
                .indvId(indv.indvId())
                .ssn(indv.ssn())
                .ssaValidationSw("Y")
                .build()));
    }

    /// Every fourth individual is enrolled in the unknown plan `ZZ`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Pln() {
        clean("STG_TRS_D_IN_MANAGED_CARE");
        validMembers();
        for (var id : individuals()) {
            tables.insert(InManagedCareDelta.builder()
                    .indvId(num(id))
                    .beginDt(pastDate(3))
                    .mcPlan(id % 4 == 0 ? "ZZ" : "PA")
                    .historySeq(BigDecimal.ONE)
                    .createDt(pastDate(1))
                    .mcProgCode("S")
                    .build());
        }
    }

    /// Every 7th main phone is too short, every 5th e-mail is not an address.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr() {
        tables.deleteRange("STG_TRS_D_DC_CASES", "CASE_NUM", CASE, CASE + 999_999);
        tables.deleteRange("STG_TRS_DC_CASE_INDV", "CASE_NUM", CASE, CASE + 999_999);
        validMembers();
        for (var id : individuals()) {
            var caseNum = num(CASE + (id - INDV));
            int i = (int) (id - INDV);
            tables.insert(DcCasesDelta.builder()
                    .caseNum(caseNum)
                    .createDt(pastDate(1))
                    .phNum(i % 7 == 0 ? "512-555-12" : "512555%04d".formatted(1000 + i))
                    .workPhNum(i % 3 == 0 ? "2145551234" : null)
                    .workPhNumExt(i % 3 == 0 ? num(12) : null)
                    .otherPhNum(i % 4 == 0 ? "8005550000" : null)
                    .email(tables.text(i % 5 == 0 ? "not an email"
                            : faker.internet().emailAddress()))
                    .build());
            tables.insert(DcCaseIndv.builder()
                    .caseNum(caseNum)
                    .indvId(num(id))
                    .build());
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw() {
        fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_OnGoing();
        validMembers();
    }

    /// Every 5th type of assistance is unknown, every 6th eligibility ends before it begins.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_TOA() {
        clean("STG_TRS_D_CV_MCI_EDG_INDV_TOA");
        validMembers();
        for (var id : individuals()) {
            var begin = pastDate(3);
            tables.insert(CvMciEdgIndvToaDelta.builder()
                    .indvId(num(id))
                    .programCd("MA")
                    .edgNum(num(EDG + (id - INDV)))
                    .mciCreateSeq(BigDecimal.ONE)
                    .historySeq(BigDecimal.ONE)
                    .caseNum(num(CASE + (id - INDV)))
                    .partStatusCd("EL")
                    .typeOfAssistanceCd(id % 5 == 0 ? "ZZ" : "A1")
                    .createDt(pastDate(1))
                    .systemCd("TR")
                    .conversionInd("C")
                    .eligEffBeginDt(begin)
                    .eligEffEndDt(id % 6 == 0 ? begin.minusDays(10) : null)
                    .convertDt(pastDate(5))
                    .build());
        }
    }

    /// Individuals related in pairs; every third pair has the unknown relationship `XX`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem() {
        clean("STG_TRS_D_DC_RELATIONSHIPS");
        validMembers();
        var ids = individuals();
        for (int i = 0; i + 1 < ids.size(); i += 2) {
            tables.insert(DcRelationshipsDelta.builder()
                    .indvId(num(ids.get(i)))
                    .refIndvId(num(ids.get(i + 1)))
                    .effBeginDt(pastDate(4))
                    .histNavInd("C")
                    .relationshipTypeCd(i % 6 == 0 ? "XX" : "PA")
                    .createDt(pastDate(2))
                    .updateDt(pastDate(1))
                    .build());
        }
    }

    /// Providers with a TPI; every 5th provider number is malformed, every 4th has no MDM provider record.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP() {
        clean("STG_TRS_D_IN_MANAGED_CARE");
        validMembers();
        tables.execute("DELETE FROM C_B_PTY_RLE_ALT_ID_XREF WHERE ROWID_OBJECT LIKE 'MOCK%'", Map.of());
        tables.execute("DELETE FROM C_B_PTY_RLE_ALT_ID WHERE ROWID_OBJECT LIKE 'MOCK%'", Map.of());
        for (var id : individuals()) {
            int i = (int) (id - INDV);
            var tpi = "%09d".formatted(700_000_000 + i);
            tables.insert(InManagedCareDelta.builder()
                    .indvId(num(id))
                    .beginDt(pastDate(2))
                    .mcPlan("PA")
                    .historySeq(BigDecimal.ONE)
                    .createDt(pastDate(1))
                    .providerNum(i % 5 == 0 ? "X12" : tpi)
                    .mcProgCode("S")
                    .build());
            if (i % 4 != 0) {
                var rowid = "MOCK" + "%010d".formatted(i);
                tables.insert(PartyRoleAltId.builder()
                        .rowidObject(rowid)
                        .altIdTp("006")
                        .altIdVal(tpi)
                        .build());
                tables.insert(PartyRoleAltIdXref.builder()
                        .rowidObject(rowid)
                        .rowidSystem("C21")
                        .hubStateInd(1)
                        .srcLastUpdDt(pastDate(1))
                        .pkeySrcObject(tpi + (i % 3 == 0 ? "|HCO|Provider" : "|HCP|Provider"))
                        .build());
            }
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Addr_1() {
        addresses();
    }

    /// Mapping 012 reads the unique addresses mapping 011 builds, so they are derived here the same way: one
    /// `STG_TRS_D_UNQ_ADDR` row per distinct pipe-joined address of `STG_TRS_D_INDV_ADDR`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Addr_2() {
        var addresses = addresses();
        validMembers();
        tables.execute("DELETE FROM STG_TRS_D_UNQ_ADDR WHERE ADDR_ID LIKE '%MOCK %'", Map.of());
        tables.insertAll(Rows.firstPerKey(addresses.stream().map(TrsMockData::uniqueAddress).toList(),
                UniqueAddressDelta::addrId));
    }

    /// Mailing (even) and physical (odd) addresses in Austin; every third one is an apartment.
    private List<IndvAddrDelta> addresses() {
        clean("STG_TRS_D_INDV_ADDR");
        return individuals().stream().map(id -> {
            int i = (int) (id - INDV);
            return tables.insert(IndvAddrDelta.builder()
                    .indvId(num(id))
                    .caseNum(num(CASE + i))
                    .edgNum(num(EDG + i))
                    .addrTypeCd(i % 2 == 0 ? "MA" : "PH")
                    .addrStNum(String.valueOf(100 + i))
                    .addrStNm(tables.text("MOCK " + faker.address().streetName().toUpperCase()))
                    .addrStTypeCd("ST")
                    .addrStDirCd("NO")
                    .addrAptNum(i % 3 == 0 ? String.valueOf(i) : null)
                    .addrDwellingTypeCd(i % 3 == 0 ? "APT" : null)
                    .addrCity(tables.text("AUSTIN"))
                    .addrStateCd("TX")
                    .addrZip5("787" + "%02d".formatted(i % 100))
                    .addrZip4("1234")
                    .effBeginDt(pastDate(3))
                    .createDt(pastDate(1))
                    .build());
        }).toList();
    }

    private static UniqueAddressDelta uniqueAddress(IndvAddrDelta a) {
        var line = concat(a.addrStNum(), " ", a.addrStNm());
        return UniqueAddressDelta.builder()
                .addrId(Arrays.stream(new String[] {a.addrStNum(), a.addrStNumFrac(),
                                a.addrStNm(), a.addrStDirCd(), a.addrStTypeCd(), a.addrDwellingTypeCd(),
                                a.addrAptNum(), a.addrLine(), a.addrCity(), a.addrStateCd(), a.addrZip5(),
                                a.addrZip4()})
                        .map(value -> Objects.toString(value, "")).collect(Collectors.joining("|")))
                .addrLn1(line)
                .city(a.addrCity())
                .state("48")
                .cntryCd("US")
                .pstlCd(a.addrZip5())
                .pstlCdExt(a.addrZip4())
                .srcAddrLn1(line)
                .srcCity(a.addrCity())
                .srcState(a.addrStateCd())
                .srcCntry("US")
                .srcPstlCd(a.addrZip5())
                .srcPstlCdExt(a.addrZip4())
                .build();
    }

    /// Oracle `||`: `NULL` concatenates as an empty string.
    private static String concat(String... parts) {
        return Arrays.stream(parts).map(part -> Objects.toString(part, "")).collect(Collectors.joining());
    }
}
