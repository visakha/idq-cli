package com.idq.cli.mock;

import static com.idq.cli.core.EntityBuilder.entity;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.MdmBaseTables.PartyRoleAltId;
import com.idq.cli.core.reference.MdmBaseTables.PartyRoleAltIdXref;
import com.idq.cli.source.trs.TrsSources.CvEdMciEdgIndv;
import com.idq.cli.source.trs.TrsSources.DCvDcMciAlias;
import com.idq.cli.source.trs.TrsSources.DCvDcMciIndv;
import com.idq.cli.source.trs.TrsSources.DCvMciEdgIndvToa;
import com.idq.cli.source.trs.TrsSources.DDcAlias;
import com.idq.cli.source.trs.TrsSources.DDcCases;
import com.idq.cli.source.trs.TrsSources.DDcIndv;
import com.idq.cli.source.trs.TrsSources.DDcPrimaryPayee;
import com.idq.cli.source.trs.TrsSources.DDcRelationships;
import com.idq.cli.source.trs.TrsSources.DInManagedCare;
import com.idq.cli.source.trs.TrsSources.DIndvAddr;
import com.idq.cli.source.trs.TrsSources.DcCaseIndv;
import com.idq.cli.source.trs.TrsSources.DcCases;
import com.idq.cli.source.trs.TrsSources.HDcIndv;
import com.idq.cli.source.trs.TrsTargets.UniqueAddress;
import com.idq.cli.source.trs.TrsTargets.ValidMember;
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
        tables.insert(entity(ValidMember.class)
                .with(ValidMember::indvId, id)
                .with(ValidMember::ptyPk, ptyPk)
                .with(ValidMember::srcTbl, sourceTable)
                .with(ValidMember::createDate, LocalDateTime.now()));
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

    private List<DDcIndv> dailyIndividuals() {
        return people().stream().map(p -> tables.insert(entity(DDcIndv.class)
                .with(DDcIndv::indvId, p.indvId())
                .with(DDcIndv::historySeq, BigDecimal.ONE)
                .with(DDcIndv::firstName, p.firstName())
                .with(DDcIndv::midName, p.midName())
                .with(DDcIndv::lastName, p.lastName())
                .with(DDcIndv::sufxName, p.sufxName())
                .with(DDcIndv::prefixName, "MR")
                .with(DDcIndv::genderCd, p.genderCd())
                .with(DDcIndv::raceCd, p.raceCd())
                .with(DDcIndv::ethnicityCd, "H")
                .with(DDcIndv::ssaValidationSw, "Y")
                .with(DDcIndv::fileClearanceSw, "Y")
                .with(DDcIndv::inactiveInd, "N")
                .with(DDcIndv::deleteSw, "N")
                .with(DDcIndv::dobDt, p.dob())
                .with(DDcIndv::createDt, p.created())
                .with(DDcIndv::ssn, p.ssn())
                .with(DDcIndv::loadDate, LocalDateTime.now()))).toList();
    }

    private void convertedIndividuals() {
        people().forEach(p -> tables.insert(entity(DCvDcMciIndv.class)
                .with(DCvDcMciIndv::indvId, p.indvId())
                .with(DCvDcMciIndv::historySeq, BigDecimal.ONE)
                .with(DCvDcMciIndv::firstName, p.firstName())
                .with(DCvDcMciIndv::midName, p.midName())
                .with(DCvDcMciIndv::lastName, p.lastName())
                .with(DCvDcMciIndv::sufxName, p.sufxName())
                .with(DCvDcMciIndv::prefixName, "MR")
                .with(DCvDcMciIndv::genderCd, p.genderCd())
                .with(DCvDcMciIndv::raceCd, p.raceCd())
                .with(DCvDcMciIndv::ethnicityCd, "H")
                .with(DCvDcMciIndv::inactiveInd, "N")
                .with(DCvDcMciIndv::dobDt, p.dob())
                .with(DCvDcMciIndv::createDt, p.created())
                .with(DCvDcMciIndv::ssn, p.ssn())
                .with(DCvDcMciIndv::twConvertInd, "Y")
                .with(DCvDcMciIndv::ltcConvertInd, "N")));
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
            tables.insert(entity(DDcPrimaryPayee.class)
                    .with(DDcPrimaryPayee::caseNum, caseNum)
                    .with(DDcPrimaryPayee::edgNum, edg)
                    .with(DDcPrimaryPayee::addrTypeCd, "MA")
                    .with(DDcPrimaryPayee::altPayeeExistsSw, "Y")
                    .with(DDcPrimaryPayee::createDt, pastDate(1)));
            tables.insert(entity(CvEdMciEdgIndv.class)
                    .with(CvEdMciEdgIndv::caseNum, caseNum)
                    .with(CvEdMciEdgIndv::edgNum, edg)
                    .with(CvEdMciEdgIndv::indvId, num(id))
                    .with(CvEdMciEdgIndv::eligEffBeginDt, pastDate(3))
                    .with(CvEdMciEdgIndv::createDt, pastDate(1)));
            tables.insert(entity(DcCases.class)
                    .with(DcCases::caseNum, caseNum)
                    .with(DcCases::authrepVerfCd, "CS")
                    .with(DcCases::sentAuthrepSw, "Y")
                    .with(DcCases::createDt, pastDate(1)));
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
                    tables.insert(entity(DDcAlias.class)
                            .with(DDcAlias::indvId, num(id))
                            .with(DDcAlias::seqNum, num(seq))
                            .with(DDcAlias::firstName, firstName)
                            .with(DDcAlias::lastName, lastName)
                            .with(DDcAlias::createDt, created));
                } else {
                    tables.insert(entity(DCvDcMciAlias.class)
                            .with(DCvDcMciAlias::indvId, num(id))
                            .with(DCvDcMciAlias::sequenceNum, num(seq))
                            .with(DCvDcMciAlias::firstName, firstName)
                            .with(DCvDcMciAlias::lastName, lastName)
                            .with(DCvDcMciAlias::createDt, created));
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
        daily.forEach(indv -> tables.insert(entity(HDcIndv.class)
                .with(HDcIndv::indvId, indv.indvId())
                .with(HDcIndv::ssn, indv.ssn())
                .with(HDcIndv::ssaValidationSw, "Y")));
    }

    /// Every fourth individual is enrolled in the unknown plan `ZZ`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Pln() {
        clean("STG_TRS_D_IN_MANAGED_CARE");
        validMembers();
        for (var id : individuals()) {
            tables.insert(entity(DInManagedCare.class)
                    .with(DInManagedCare::indvId, num(id))
                    .with(DInManagedCare::beginDt, pastDate(3))
                    .with(DInManagedCare::mcPlan, id % 4 == 0 ? "ZZ" : "PA")
                    .with(DInManagedCare::historySeq, BigDecimal.ONE)
                    .with(DInManagedCare::createDt, pastDate(1))
                    .with(DInManagedCare::mcProgCode, "S"));
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
            tables.insert(entity(DDcCases.class)
                    .with(DDcCases::caseNum, caseNum)
                    .with(DDcCases::createDt, pastDate(1))
                    .with(DDcCases::phNum, i % 7 == 0 ? "512-555-12" : "512555%04d".formatted(1000 + i))
                    .with(DDcCases::workPhNum, i % 3 == 0 ? "2145551234" : null)
                    .with(DDcCases::workPhNumExt, i % 3 == 0 ? num(12) : null)
                    .with(DDcCases::otherPhNum, i % 4 == 0 ? "8005550000" : null)
                    .with(DDcCases::email, tables.text(i % 5 == 0 ? "not an email"
                            : faker.internet().emailAddress())));
            tables.insert(entity(DcCaseIndv.class)
                    .with(DcCaseIndv::caseNum, caseNum)
                    .with(DcCaseIndv::indvId, num(id)));
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
            tables.insert(entity(DCvMciEdgIndvToa.class)
                    .with(DCvMciEdgIndvToa::indvId, num(id))
                    .with(DCvMciEdgIndvToa::programCd, "MA")
                    .with(DCvMciEdgIndvToa::edgNum, num(EDG + (id - INDV)))
                    .with(DCvMciEdgIndvToa::mciCreateSeq, BigDecimal.ONE)
                    .with(DCvMciEdgIndvToa::historySeq, BigDecimal.ONE)
                    .with(DCvMciEdgIndvToa::caseNum, num(CASE + (id - INDV)))
                    .with(DCvMciEdgIndvToa::partStatusCd, "EL")
                    .with(DCvMciEdgIndvToa::typeOfAssistanceCd, id % 5 == 0 ? "ZZ" : "A1")
                    .with(DCvMciEdgIndvToa::createDt, pastDate(1))
                    .with(DCvMciEdgIndvToa::systemCd, "TR")
                    .with(DCvMciEdgIndvToa::conversionInd, "C")
                    .with(DCvMciEdgIndvToa::eligEffBeginDt, begin)
                    .with(DCvMciEdgIndvToa::eligEffEndDt, id % 6 == 0 ? begin.minusDays(10) : null)
                    .with(DCvMciEdgIndvToa::convertDt, pastDate(5)));
        }
    }

    /// Individuals related in pairs; every third pair has the unknown relationship `XX`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem() {
        clean("STG_TRS_D_DC_RELATIONSHIPS");
        validMembers();
        var ids = individuals();
        for (int i = 0; i + 1 < ids.size(); i += 2) {
            tables.insert(entity(DDcRelationships.class)
                    .with(DDcRelationships::indvId, num(ids.get(i)))
                    .with(DDcRelationships::refIndvId, num(ids.get(i + 1)))
                    .with(DDcRelationships::effBeginDt, pastDate(4))
                    .with(DDcRelationships::histNavInd, "C")
                    .with(DDcRelationships::relationshipTypeCd, i % 6 == 0 ? "XX" : "PA")
                    .with(DDcRelationships::createDt, pastDate(2))
                    .with(DDcRelationships::updateDt, pastDate(1)));
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
            tables.insert(entity(DInManagedCare.class)
                    .with(DInManagedCare::indvId, num(id))
                    .with(DInManagedCare::beginDt, pastDate(2))
                    .with(DInManagedCare::mcPlan, "PA")
                    .with(DInManagedCare::historySeq, BigDecimal.ONE)
                    .with(DInManagedCare::createDt, pastDate(1))
                    .with(DInManagedCare::providerNum, i % 5 == 0 ? "X12" : tpi)
                    .with(DInManagedCare::mcProgCode, "S"));
            if (i % 4 != 0) {
                var rowid = "MOCK" + "%010d".formatted(i);
                tables.insert(entity(PartyRoleAltId.class)
                        .with(PartyRoleAltId::rowidObject, rowid)
                        .with(PartyRoleAltId::altIdTp, "006")
                        .with(PartyRoleAltId::altIdVal, tpi));
                tables.insert(entity(PartyRoleAltIdXref.class)
                        .with(PartyRoleAltIdXref::rowidObject, rowid)
                        .with(PartyRoleAltIdXref::rowidSystem, "C21")
                        .with(PartyRoleAltIdXref::hubStateInd, 1)
                        .with(PartyRoleAltIdXref::srcLastUpdDt, pastDate(1))
                        .with(PartyRoleAltIdXref::pkeySrcObject,
                                tpi + (i % 3 == 0 ? "|HCO|Provider" : "|HCP|Provider")));
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
                UniqueAddress::addrId));
    }

    /// Mailing (even) and physical (odd) addresses in Austin; every third one is an apartment.
    private List<DIndvAddr> addresses() {
        clean("STG_TRS_D_INDV_ADDR");
        return individuals().stream().map(id -> {
            int i = (int) (id - INDV);
            return tables.insert(entity(DIndvAddr.class)
                    .with(DIndvAddr::indvId, num(id))
                    .with(DIndvAddr::caseNum, num(CASE + i))
                    .with(DIndvAddr::edgNum, num(EDG + i))
                    .with(DIndvAddr::addrTypeCd, i % 2 == 0 ? "MA" : "PH")
                    .with(DIndvAddr::addrStNum, String.valueOf(100 + i))
                    .with(DIndvAddr::addrStNm, tables.text("MOCK " + faker.address().streetName().toUpperCase()))
                    .with(DIndvAddr::addrStTypeCd, "ST")
                    .with(DIndvAddr::addrStDirCd, "NO")
                    .with(DIndvAddr::addrAptNum, i % 3 == 0 ? String.valueOf(i) : null)
                    .with(DIndvAddr::addrDwellingTypeCd, i % 3 == 0 ? "APT" : null)
                    .with(DIndvAddr::addrCity, tables.text("AUSTIN"))
                    .with(DIndvAddr::addrStateCd, "TX")
                    .with(DIndvAddr::addrZip5, "787" + "%02d".formatted(i % 100))
                    .with(DIndvAddr::addrZip4, "1234")
                    .with(DIndvAddr::effBeginDt, pastDate(3))
                    .with(DIndvAddr::createDt, pastDate(1)));
        }).toList();
    }

    private static UniqueAddress uniqueAddress(DIndvAddr a) {
        var line = concat(a.addrStNum(), " ", a.addrStNm());
        return entity(UniqueAddress.class)
                .with(UniqueAddress::addrId, Arrays.stream(new String[] {a.addrStNum(), a.addrStNumFrac(),
                                a.addrStNm(), a.addrStDirCd(), a.addrStTypeCd(), a.addrDwellingTypeCd(),
                                a.addrAptNum(), a.addrLine(), a.addrCity(), a.addrStateCd(), a.addrZip5(),
                                a.addrZip4()})
                        .map(value -> Objects.toString(value, "")).collect(Collectors.joining("|")))
                .with(UniqueAddress::addrLn1, line)
                .with(UniqueAddress::city, a.addrCity())
                .with(UniqueAddress::state, "48")
                .with(UniqueAddress::cntryCd, "US")
                .with(UniqueAddress::pstlCd, a.addrZip5())
                .with(UniqueAddress::pstlCdExt, a.addrZip4())
                .with(UniqueAddress::srcAddrLn1, line)
                .with(UniqueAddress::srcCity, a.addrCity())
                .with(UniqueAddress::srcState, a.addrStateCd())
                .with(UniqueAddress::srcCntry, "US")
                .with(UniqueAddress::srcPstlCd, a.addrZip5())
                .with(UniqueAddress::srcPstlCdExt, a.addrZip4())
                .build();
    }

    /// Oracle `||`: `NULL` concatenates as an empty string.
    private static String concat(String... parts) {
        return Arrays.stream(parts).map(part -> Objects.toString(part, "")).collect(Collectors.joining());
    }
}
