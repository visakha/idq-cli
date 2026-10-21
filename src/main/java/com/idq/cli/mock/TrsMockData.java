package com.idq.cli.mock;

import static com.idq.cli.core.EntityBuilder.entity;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.MdmBaseTables.PartyRoleAltId;
import com.idq.cli.core.reference.MdmBaseTables.PartyRoleAltIdXref;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvEdMciEdgIndv;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvDcMciAliasDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvDcMciIndvDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.CvMciEdgIndvToaDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcAliasDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcCasesDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcIndvDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcPrimaryPayeeDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcRelationshipsDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.InManagedCareDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.IndvAddrDelta;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcCaseIndv;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcCases;
import com.idq.cli.source.trs.etldb.models.TrsSources.DcIndvHist;
import com.idq.cli.source.trs.etldb.models.TrsTargets.UniqueAddressDelta;
import com.idq.cli.source.trs.etldb.models.TrsTargets.ValidMember;
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

    private List<DcIndvDelta> dailyIndividuals() {
        return people().stream().map(p -> tables.insert(entity(DcIndvDelta.class)
                .with(DcIndvDelta::indvId, p.indvId())
                .with(DcIndvDelta::historySeq, BigDecimal.ONE)
                .with(DcIndvDelta::firstName, p.firstName())
                .with(DcIndvDelta::midName, p.midName())
                .with(DcIndvDelta::lastName, p.lastName())
                .with(DcIndvDelta::sufxName, p.sufxName())
                .with(DcIndvDelta::prefixName, "MR")
                .with(DcIndvDelta::genderCd, p.genderCd())
                .with(DcIndvDelta::raceCd, p.raceCd())
                .with(DcIndvDelta::ethnicityCd, "H")
                .with(DcIndvDelta::ssaValidationSw, "Y")
                .with(DcIndvDelta::fileClearanceSw, "Y")
                .with(DcIndvDelta::inactiveInd, "N")
                .with(DcIndvDelta::deleteSw, "N")
                .with(DcIndvDelta::dobDt, p.dob())
                .with(DcIndvDelta::createDt, p.created())
                .with(DcIndvDelta::ssn, p.ssn())
                .with(DcIndvDelta::loadDate, LocalDateTime.now()))).toList();
    }

    private void convertedIndividuals() {
        people().forEach(p -> tables.insert(entity(CvDcMciIndvDelta.class)
                .with(CvDcMciIndvDelta::indvId, p.indvId())
                .with(CvDcMciIndvDelta::historySeq, BigDecimal.ONE)
                .with(CvDcMciIndvDelta::firstName, p.firstName())
                .with(CvDcMciIndvDelta::midName, p.midName())
                .with(CvDcMciIndvDelta::lastName, p.lastName())
                .with(CvDcMciIndvDelta::sufxName, p.sufxName())
                .with(CvDcMciIndvDelta::prefixName, "MR")
                .with(CvDcMciIndvDelta::genderCd, p.genderCd())
                .with(CvDcMciIndvDelta::raceCd, p.raceCd())
                .with(CvDcMciIndvDelta::ethnicityCd, "H")
                .with(CvDcMciIndvDelta::inactiveInd, "N")
                .with(CvDcMciIndvDelta::dobDt, p.dob())
                .with(CvDcMciIndvDelta::createDt, p.created())
                .with(CvDcMciIndvDelta::ssn, p.ssn())
                .with(CvDcMciIndvDelta::twConvertInd, "Y")
                .with(CvDcMciIndvDelta::ltcConvertInd, "N")));
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
            tables.insert(entity(DcPrimaryPayeeDelta.class)
                    .with(DcPrimaryPayeeDelta::caseNum, caseNum)
                    .with(DcPrimaryPayeeDelta::edgNum, edg)
                    .with(DcPrimaryPayeeDelta::addrTypeCd, "MA")
                    .with(DcPrimaryPayeeDelta::altPayeeExistsSw, "Y")
                    .with(DcPrimaryPayeeDelta::createDt, pastDate(1)));
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
                    tables.insert(entity(DcAliasDelta.class)
                            .with(DcAliasDelta::indvId, num(id))
                            .with(DcAliasDelta::seqNum, num(seq))
                            .with(DcAliasDelta::firstName, firstName)
                            .with(DcAliasDelta::lastName, lastName)
                            .with(DcAliasDelta::createDt, created));
                } else {
                    tables.insert(entity(CvDcMciAliasDelta.class)
                            .with(CvDcMciAliasDelta::indvId, num(id))
                            .with(CvDcMciAliasDelta::sequenceNum, num(seq))
                            .with(CvDcMciAliasDelta::firstName, firstName)
                            .with(CvDcMciAliasDelta::lastName, lastName)
                            .with(CvDcMciAliasDelta::createDt, created));
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
        daily.forEach(indv -> tables.insert(entity(DcIndvHist.class)
                .with(DcIndvHist::indvId, indv.indvId())
                .with(DcIndvHist::ssn, indv.ssn())
                .with(DcIndvHist::ssaValidationSw, "Y")));
    }

    /// Every fourth individual is enrolled in the unknown plan `ZZ`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Pln() {
        clean("STG_TRS_D_IN_MANAGED_CARE");
        validMembers();
        for (var id : individuals()) {
            tables.insert(entity(InManagedCareDelta.class)
                    .with(InManagedCareDelta::indvId, num(id))
                    .with(InManagedCareDelta::beginDt, pastDate(3))
                    .with(InManagedCareDelta::mcPlan, id % 4 == 0 ? "ZZ" : "PA")
                    .with(InManagedCareDelta::historySeq, BigDecimal.ONE)
                    .with(InManagedCareDelta::createDt, pastDate(1))
                    .with(InManagedCareDelta::mcProgCode, "S"));
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
            tables.insert(entity(DcCasesDelta.class)
                    .with(DcCasesDelta::caseNum, caseNum)
                    .with(DcCasesDelta::createDt, pastDate(1))
                    .with(DcCasesDelta::phNum, i % 7 == 0 ? "512-555-12" : "512555%04d".formatted(1000 + i))
                    .with(DcCasesDelta::workPhNum, i % 3 == 0 ? "2145551234" : null)
                    .with(DcCasesDelta::workPhNumExt, i % 3 == 0 ? num(12) : null)
                    .with(DcCasesDelta::otherPhNum, i % 4 == 0 ? "8005550000" : null)
                    .with(DcCasesDelta::email, tables.text(i % 5 == 0 ? "not an email"
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
            tables.insert(entity(CvMciEdgIndvToaDelta.class)
                    .with(CvMciEdgIndvToaDelta::indvId, num(id))
                    .with(CvMciEdgIndvToaDelta::programCd, "MA")
                    .with(CvMciEdgIndvToaDelta::edgNum, num(EDG + (id - INDV)))
                    .with(CvMciEdgIndvToaDelta::mciCreateSeq, BigDecimal.ONE)
                    .with(CvMciEdgIndvToaDelta::historySeq, BigDecimal.ONE)
                    .with(CvMciEdgIndvToaDelta::caseNum, num(CASE + (id - INDV)))
                    .with(CvMciEdgIndvToaDelta::partStatusCd, "EL")
                    .with(CvMciEdgIndvToaDelta::typeOfAssistanceCd, id % 5 == 0 ? "ZZ" : "A1")
                    .with(CvMciEdgIndvToaDelta::createDt, pastDate(1))
                    .with(CvMciEdgIndvToaDelta::systemCd, "TR")
                    .with(CvMciEdgIndvToaDelta::conversionInd, "C")
                    .with(CvMciEdgIndvToaDelta::eligEffBeginDt, begin)
                    .with(CvMciEdgIndvToaDelta::eligEffEndDt, id % 6 == 0 ? begin.minusDays(10) : null)
                    .with(CvMciEdgIndvToaDelta::convertDt, pastDate(5)));
        }
    }

    /// Individuals related in pairs; every third pair has the unknown relationship `XX`.
    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem() {
        clean("STG_TRS_D_DC_RELATIONSHIPS");
        validMembers();
        var ids = individuals();
        for (int i = 0; i + 1 < ids.size(); i += 2) {
            tables.insert(entity(DcRelationshipsDelta.class)
                    .with(DcRelationshipsDelta::indvId, num(ids.get(i)))
                    .with(DcRelationshipsDelta::refIndvId, num(ids.get(i + 1)))
                    .with(DcRelationshipsDelta::effBeginDt, pastDate(4))
                    .with(DcRelationshipsDelta::histNavInd, "C")
                    .with(DcRelationshipsDelta::relationshipTypeCd, i % 6 == 0 ? "XX" : "PA")
                    .with(DcRelationshipsDelta::createDt, pastDate(2))
                    .with(DcRelationshipsDelta::updateDt, pastDate(1)));
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
            tables.insert(entity(InManagedCareDelta.class)
                    .with(InManagedCareDelta::indvId, num(id))
                    .with(InManagedCareDelta::beginDt, pastDate(2))
                    .with(InManagedCareDelta::mcPlan, "PA")
                    .with(InManagedCareDelta::historySeq, BigDecimal.ONE)
                    .with(InManagedCareDelta::createDt, pastDate(1))
                    .with(InManagedCareDelta::providerNum, i % 5 == 0 ? "X12" : tpi)
                    .with(InManagedCareDelta::mcProgCode, "S"));
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
                UniqueAddressDelta::addrId));
    }

    /// Mailing (even) and physical (odd) addresses in Austin; every third one is an apartment.
    private List<IndvAddrDelta> addresses() {
        clean("STG_TRS_D_INDV_ADDR");
        return individuals().stream().map(id -> {
            int i = (int) (id - INDV);
            return tables.insert(entity(IndvAddrDelta.class)
                    .with(IndvAddrDelta::indvId, num(id))
                    .with(IndvAddrDelta::caseNum, num(CASE + i))
                    .with(IndvAddrDelta::edgNum, num(EDG + i))
                    .with(IndvAddrDelta::addrTypeCd, i % 2 == 0 ? "MA" : "PH")
                    .with(IndvAddrDelta::addrStNum, String.valueOf(100 + i))
                    .with(IndvAddrDelta::addrStNm, tables.text("MOCK " + faker.address().streetName().toUpperCase()))
                    .with(IndvAddrDelta::addrStTypeCd, "ST")
                    .with(IndvAddrDelta::addrStDirCd, "NO")
                    .with(IndvAddrDelta::addrAptNum, i % 3 == 0 ? String.valueOf(i) : null)
                    .with(IndvAddrDelta::addrDwellingTypeCd, i % 3 == 0 ? "APT" : null)
                    .with(IndvAddrDelta::addrCity, tables.text("AUSTIN"))
                    .with(IndvAddrDelta::addrStateCd, "TX")
                    .with(IndvAddrDelta::addrZip5, "787" + "%02d".formatted(i % 100))
                    .with(IndvAddrDelta::addrZip4, "1234")
                    .with(IndvAddrDelta::effBeginDt, pastDate(3))
                    .with(IndvAddrDelta::createDt, pastDate(1)));
        }).toList();
    }

    private static UniqueAddressDelta uniqueAddress(IndvAddrDelta a) {
        var line = concat(a.addrStNum(), " ", a.addrStNm());
        return entity(UniqueAddressDelta.class)
                .with(UniqueAddressDelta::addrId, Arrays.stream(new String[] {a.addrStNum(), a.addrStNumFrac(),
                                a.addrStNm(), a.addrStDirCd(), a.addrStTypeCd(), a.addrDwellingTypeCd(),
                                a.addrAptNum(), a.addrLine(), a.addrCity(), a.addrStateCd(), a.addrZip5(),
                                a.addrZip4()})
                        .map(value -> Objects.toString(value, "")).collect(Collectors.joining("|")))
                .with(UniqueAddressDelta::addrLn1, line)
                .with(UniqueAddressDelta::city, a.addrCity())
                .with(UniqueAddressDelta::state, "48")
                .with(UniqueAddressDelta::cntryCd, "US")
                .with(UniqueAddressDelta::pstlCd, a.addrZip5())
                .with(UniqueAddressDelta::pstlCdExt, a.addrZip4())
                .with(UniqueAddressDelta::srcAddrLn1, line)
                .with(UniqueAddressDelta::srcCity, a.addrCity())
                .with(UniqueAddressDelta::srcState, a.addrStateCd())
                .with(UniqueAddressDelta::srcCntry, "US")
                .with(UniqueAddressDelta::srcPstlCd, a.addrZip5())
                .with(UniqueAddressDelta::srcPstlCdExt, a.addrZip4())
                .build();
    }

    /// Oracle `||`: `NULL` concatenates as an empty string.
    private static String concat(String... parts) {
        return Arrays.stream(parts).map(part -> Objects.toString(part, "")).collect(Collectors.joining());
    }
}
