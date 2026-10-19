package com.idq.cli.mock;

import static com.idq.cli.mock.MockTables.row;

import com.idq.cli.config.EtlSettings;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Random;
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

    List<Long> individuals() {
        return LongStream.rangeClosed(1, settings.mockRowsPerTable()).map(i -> INDV + i).boxed().toList();
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
            tables.insert("STG_TRS_VALID_MEMBERS", row("INDV_ID", id, "PTY_PK", String.valueOf(id), "SRC_TBL", "MCI",
                    "CREATE_DATE", LocalDateTime.now()));
            if (id % 2 == 0) {
                tables.insert("STG_TRS_VALID_MEMBERS", row("INDV_ID", id, "PTY_PK", id + "|DC_INDV", "SRC_TBL",
                        "DC_INDV", "CREATE_DATE", LocalDateTime.now()));
            }
        }
    }

    private LocalDateTime pastDate(int years) {
        return LocalDateTime.now().minusDays(faker.number().numberBetween(30, 365L * years)).withNano(0);
    }

    private void individuals(String table, boolean daily) {
        for (var id : individuals()) {
            int i = (int) (id - INDV);
            tables.insert(table, row("INDV_ID", id, "HISTORY_SEQ", 1, "FIRST_NAME", i == 3 ? null : faker.name()
                    .firstName(), "MID_NAME", faker.name().firstName().substring(0, 1), "LAST_NAME",
                    faker.name().lastName(), "SUFX_NAME", i % 5 == 0 ? "JR" : null, "PREFIX_NAME", "MR",
                    "GENDER_CD", i % 7 == 0 ? "X" : faker.options().option("M", "F"), "RACE_CD",
                    i % 6 == 0 ? "Z" : "W", "ETHNICITY_CD", "H", "SSA_VALIDATION_SW", "Y", "FILE_CLEARANCE_SW", "Y",
                    "INACTIVE_IND", "N", "DELETE_SW", "N", "DOB_DT", i == 4 ? LocalDateTime.now().plusYears(1)
                    : pastDate(80), "CREATE_DT", pastDate(2), "SSN", 100_000_000L + faker.number().numberBetween(1,
                    665_000_000), "TW_CONVERT_IND", daily ? null : "Y", "LTC_CONVERT_IND", daily ? null : "N",
                    "LOAD_DATE", LocalDateTime.now()));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_OnGoing() {
        clean("STG_TRS_D_DC_INDV", "STG_TRS_D_CV_DC_MCI_INDV", "STG_TRS_D_CV_MCI_EDG_INDV_TOA");
        individuals("STG_TRS_D_DC_INDV", true);
        individuals("STG_TRS_D_CV_DC_MCI_INDV", false);
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing() {
        tables.deleteRange("STG_TRS_D_DC_PRIMARY_PAYEE", "CASE_NUM", CASE, CASE + 999_999);
        tables.deleteRange("STG_TRS_CV_ED_MCI_EDG_INDV", "CASE_NUM", CASE, CASE + 999_999);
        tables.deleteRange("STG_TRS_DC_CASES", "CASE_NUM", CASE, CASE + 999_999);
        validMembers();
        for (var id : individuals()) {
            long caseNum = CASE + (id - INDV);
            long edg = EDG + (id - INDV);
            tables.insert("STG_TRS_D_DC_PRIMARY_PAYEE", row("CASE_NUM", caseNum, "EDG_NUM", edg, "ADDR_TYPE_CD", "MA",
                    "ALT_PAYEE_EXISTS_SW", "Y", "CREATE_DT", pastDate(1)));
            tables.insert("STG_TRS_CV_ED_MCI_EDG_INDV", row("CASE_NUM", caseNum, "EDG_NUM", edg, "INDV_ID", id,
                    "ELIG_EFF_BEGIN_DT", pastDate(3), "CREATE_DT", pastDate(1)));
            tables.insert("STG_TRS_DC_CASES", row("CASE_NUM", caseNum, "AUTHREP_VERF_CD", "CS", "SENT_AUTHREP_SW",
                    "Y", "CREATE_DT", pastDate(1)));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Nm() {
        clean("STG_TRS_D_CV_DC_MCI_ALIAS", "STG_TRS_D_DC_ALIAS");
        validMembers();
        for (var id : individuals()) {
            for (int seq = 1; seq <= 2; seq++) {
                var alias = row("INDV_ID", id, "FIRST_NAME", faker.name().firstName() + (seq == 2 ? "0n" : ""),
                        "MID_NAME", null, "LAST_NAME", faker.name().lastName(), "CREATE_DT", pastDate(2),
                        "SEQUENCE_NUM", seq, "SEQ_NUM", seq);
                tables.insert(id % 2 == 0 ? "STG_TRS_D_DC_ALIAS" : "STG_TRS_D_CV_DC_MCI_ALIAS", alias);
            }
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id() {
        clean("STG_TRS_D_DC_INDV", "STG_TRS_D_CV_DC_MCI_INDV", "STG_TRS_H_DC_INDV", "STG_TRS_D_CV_DC_MRG_SPRT_INDV");
        validMembers();
        individuals("STG_TRS_D_DC_INDV", true);
        individuals("STG_TRS_D_CV_DC_MCI_INDV", false);
        tables.execute("""
                INSERT INTO STG_TRS_H_DC_INDV (INDV_ID, SSN, SSA_VALIDATION_SW)
                SELECT INDV_ID, SSN, 'Y' FROM STG_TRS_D_DC_INDV WHERE INDV_ID BETWEEN :f AND :t
                """, java.util.Map.of("f", INDV, "t", INDV + 999_999));
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Pln() {
        clean("STG_TRS_D_IN_MANAGED_CARE");
        validMembers();
        for (var id : individuals()) {
            tables.insert("STG_TRS_D_IN_MANAGED_CARE", row("INDV_ID", id, "BEGIN_DT", pastDate(3), "END_DT", null,
                    "MC_PLAN", id % 4 == 0 ? "ZZ" : "PA", "HISTORY_SEQ", 1, "CREATE_DT", pastDate(1),
                    "MC_PROG_CODE", "S"));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr() {
        tables.deleteRange("STG_TRS_D_DC_CASES", "CASE_NUM", CASE, CASE + 999_999);
        tables.deleteRange("STG_TRS_DC_CASE_INDV", "CASE_NUM", CASE, CASE + 999_999);
        validMembers();
        for (var id : individuals()) {
            long caseNum = CASE + (id - INDV);
            int i = (int) (id - INDV);
            tables.insert("STG_TRS_D_DC_CASES", row("CASE_NUM", caseNum, "CREATE_DT", pastDate(1), "PH_NUM",
                    i % 7 == 0 ? "512-555-12" : "512555%04d".formatted(1000 + i),
                    "WORK_PH_NUM", i % 3 == 0 ? "2145551234" : null,
                    "WORK_PH_NUM_EXT", i % 3 == 0 ? 12 : null, "OTHER_PH_NUM", i % 4 == 0 ? "8005550000" : null,
                    "EMAIL", i % 5 == 0 ? "not an email" : faker.internet().emailAddress()));
            tables.insert("STG_TRS_DC_CASE_INDV", row("CASE_NUM", caseNum, "INDV_ID", id));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw() {
        fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_OnGoing();
        validMembers();
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_TOA() {
        clean("STG_TRS_D_CV_MCI_EDG_INDV_TOA");
        validMembers();
        for (var id : individuals()) {
            var begin = pastDate(3);
            tables.insert("STG_TRS_D_CV_MCI_EDG_INDV_TOA", row("INDV_ID", id, "PROGRAM_CD", "MA", "EDG_NUM",
                    EDG + (id - INDV), "MCI_CREATE_SEQ", 1, "HISTORY_SEQ", 1, "CASE_NUM", CASE + (id - INDV),
                    "PART_STATUS_CD", "EL", "TYPE_OF_ASSISTANCE_CD", id % 5 == 0 ? "ZZ" : "A1", "CREATE_DT",
                    pastDate(1), "SYSTEM_CD", "TR", "CONVERSION_IND", "C", "ELIG_EFF_BEGIN_DT", begin,
                    "ELIG_EFF_END_DT", id % 6 == 0 ? begin.minusDays(10) : null, "CONVERT_DT", pastDate(5)));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem() {
        clean("STG_TRS_D_DC_RELATIONSHIPS");
        validMembers();
        var ids = individuals();
        for (int i = 0; i + 1 < ids.size(); i += 2) {
            var begin = pastDate(4);
            tables.insert("STG_TRS_D_DC_RELATIONSHIPS", row("INDV_ID", ids.get(i), "REF_INDV_ID", ids.get(i + 1),
                    "EFF_BEGIN_DT", begin, "EFF_END_DT", null, "HIST_NAV_IND", "C", "RELATIONSHIP_TYPE_CD",
                    i % 6 == 0 ? "XX" : "PA", "CREATE_DT", pastDate(2), "UPDATE_DT", pastDate(1)));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP() {
        clean("STG_TRS_D_IN_MANAGED_CARE");
        validMembers();
        tables.execute("DELETE FROM C_B_PTY_RLE_ALT_ID_XREF WHERE ROWID_OBJECT LIKE 'MOCK%'", java.util.Map.of());
        tables.execute("DELETE FROM C_B_PTY_RLE_ALT_ID WHERE ROWID_OBJECT LIKE 'MOCK%'", java.util.Map.of());
        for (var id : individuals()) {
            int i = (int) (id - INDV);
            var tpi = "%09d".formatted(700_000_000 + i);
            tables.insert("STG_TRS_D_IN_MANAGED_CARE", row("INDV_ID", id, "BEGIN_DT", pastDate(2), "MC_PLAN",
                    "PA", "HISTORY_SEQ", 1, "CREATE_DT", pastDate(1), "PROVIDER_NUM", i % 5 == 0 ? "X12" : tpi,
                    "MC_PROG_CODE", "S"));
            if (i % 4 != 0) {
                var rowid = "MOCK" + "%010d".formatted(i);
                tables.insert("C_B_PTY_RLE_ALT_ID", row("ROWID_OBJECT", rowid, "ALT_ID_TP", "006", "ALT_ID_VAL",
                        tpi));
                tables.insert("C_B_PTY_RLE_ALT_ID_XREF", row("ROWID_OBJECT", rowid, "ROWID_SYSTEM", "C21",
                        "HUB_STATE_IND", 1, "SRC_LAST_UPD_DT", pastDate(1), "PKEY_SRC_OBJECT",
                        tpi + (i % 3 == 0 ? "|HCO|Provider" : "|HCP|Provider")));
            }
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Addr_1() {
        clean("STG_TRS_D_INDV_ADDR");
        for (var id : individuals()) {
            int i = (int) (id - INDV);
            var begin = pastDate(3);
            tables.insert("STG_TRS_D_INDV_ADDR", row("INDV_ID", id, "CASE_NUM", CASE + i, "EDG_NUM", EDG + i,
                    "ADDR_TYPE_CD", i % 2 == 0 ? "MA" : "PH", "ADDR_ST_NUM", String.valueOf(100 + i),
                    "ADDR_ST_NM", "MOCK " + faker.address().streetName().toUpperCase(), "ADDR_ST_TYPE_CD", "ST",
                    "ADDR_ST_DIR_CD", "NO", "ADDR_APT_NUM", i % 3 == 0 ? String.valueOf(i) : null,
                    "ADDR_DWELLING_TYPE_CD", i % 3 == 0 ? "APT" : null, "ADDR_CITY", "AUSTIN", "ADDR_STATE_CD", "TX",
                    "ADDR_ZIP5", "787" + "%02d".formatted(i % 100), "ADDR_ZIP4", "1234", "EFF_BEGIN_DT", begin,
                    "EFF_END_DT", null, "CREATE_DT", pastDate(1), "UPDATE_DT", null));
        }
    }

    public void fill_sample_mock_data_m_Tgt_C_S_TRS_Addr_2() {
        fill_sample_mock_data_m_Tgt_C_S_TRS_Addr_1();
        validMembers();
        tables.execute("DELETE FROM STG_TRS_D_UNQ_ADDR WHERE ADDR_ID LIKE '%|MOCK %'", java.util.Map.of());
        tables.execute("""
                INSERT INTO STG_TRS_D_UNQ_ADDR (ADDR_ID, ADDR_LN_1, ADDR_LN_2, CITY, STATE, CNTRY_CD, PSTL_CD,
                    PSTL_CD_EXT, SRC_ADDR_LN_1, SRC_CITY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT)
                SELECT DISTINCT a.addr_st_num || '|' || a.addr_st_num_frac || '|' || a.addr_st_nm || '|'
                       || a.addr_st_dir_cd || '|' || a.addr_st_type_cd || '|' || a.addr_dwelling_type_cd || '|'
                       || a.addr_apt_num || '|' || a.addr_line || '|' || a.addr_city || '|' || a.addr_state_cd || '|'
                       || a.addr_zip5 || '|' || a.addr_zip4,
                       a.addr_st_num || ' ' || a.addr_st_nm, NULL, a.addr_city, '48', 'US', a.addr_zip5, a.addr_zip4,
                       a.addr_st_num || ' ' || a.addr_st_nm, a.addr_city, a.addr_state_cd, 'US', a.addr_zip5,
                       a.addr_zip4
                FROM STG_TRS_D_INDV_ADDR a
                WHERE a.indv_id BETWEEN :f AND :t
                """, java.util.Map.of("f", INDV, "t", INDV + 999_999));
    }
}
