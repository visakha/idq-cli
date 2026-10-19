package com.idq.cli.mock;

import static com.idq.cli.mock.MockTables.MARKER;
import static com.idq.cli.mock.MockTables.row;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/// Seeds the shared lookup tables with the codes the mock source rows use: code translations, exception catalog,
/// area codes, junk names and TIERS street types. Seeded rows carry the mock marker and are replaced on every call.
@Component
public class ReferenceMockData {

    static final List<String> SOURCES = List.of("TRS", "ECI", "FSS", "TTF", "WIC");

    static final List<String> EXCEPTIONS = List.of("Missing_First_Name", "Missing_Last_Name", "Invalid_First_Name",
            "Invalid_Last_Name", "Invalid_Birth_Date", "Invalid_Death_Date", "Invalid_Gender", "Invalid_Race",
            "Invalid_Ethnicity", "Invalid_Language", "Invalid_Suffix", "Invalid_Prefix", "Invalid_SSN",
            "Invalid_Medicaid_Id", "Invalid_Member_Id", "Invalid_Phone_Number", "Missing_AreaCode",
            "Invalid_Phone_Number_Ext", "Invalid_Email", "Invalid_Plan", "Invalid_TOA", "Invalid_Rel_Type",
            "Invalid_Member", "Invalid_Ref_Member", "Invalid_PCP", "Invalid_Relationship", "Invalid_Address",
            "Period_Start_Date_>_Period_End_Date");

    private final MockTables tables;

    public ReferenceMockData(MockTables tables) {
        this.tables = tables;
    }

    public void seed() {
        var now = LocalDateTime.now();
        tables.deleteMarked("EXC_LOOKUP_CODE_VALUE", "CREATED_BY");
        for (int i = 0; i < EXCEPTIONS.size(); i++) {
            var code = EXCEPTIONS.get(i);
            tables.insert("EXC_LOOKUP_CODE_VALUE", row("EXC_LOOKUP_CODE_VALUE_ID", 990000 + i, "CREATED_BY", MARKER,
                    "CREATE_DATE", now, "EXCEPTION_CODE", code, "EXCEPTION_DESC", code.replace('_', ' '),
                    "EXCEPTION_TYPE", "Bad Value"));
        }

        tables.deleteMarked("LOOKUP_CODE_VALUE", "CREATED_BY");
        codeValue("TOA", "TRS", "A1", "100", "Medicaid TOA 100");
        codeValue("TOA", "TRS", "B2", "200", "Medicaid TOA 200");
        for (var usage : List.of("001", "002", "003")) {
            codeValue("PHN_USG_TP", "TRS", usage, usage, "Usage " + usage);
        }
        for (var type : List.of("002", "004", "007")) {
            codeValue("ALT_ID_TP", "TRS", type, type, "Alternate id " + type);
        }
        codeValue("REL_TP", "ECI", "1", "MTH", "Mother");
        codeValue("INVERSE_REL", "ECI", "1|M", "SON", "Son");
        codeValue("INVERSE_REL", "ECI", "1|F", "DAU", "Daughter");
        codeValue("REL_TP", "FSS", "MOTHER|F", "MTH", "Mother");
        codeValue("INVERSE_REL", "FSS", "MOTHER|M", "SON", "Son");
        codeValue("INVERSE_REL", "FSS", "MOTHER|F", "DAU", "Daughter");

        viewCode("PLAN_CD", "MAX", "PA", "PLANA");
        viewCode("PTY_REL", "TRS", "PA", "PAR");
        viewCode("PTY_REL", "TRS", "CH", "CHL");
        viewCode("ADDR_TP", "TRS", "MA", "002");
        viewCode("ADDR_TP", "TRS", "PH", "001");
        viewCode("ADDR_TP", "ECI", "1", "002");
        for (var source : SOURCES) {
            viewCode("RACE", source, "W", "001");
            viewCode("ETHNICITY", source, "H", "1");
            viewCode("ETHNICITY", source, "1", "1");
            viewCode("ETHNICITY", source, "55", "1");
            viewCode("LANGUAGE_CD", source, "ENG", "EN");
            viewCode("LANGUAGE_CD", source, "1", "EN");
            viewCode("SUFFIX", source, "JR", "JR");
            viewCode("PREFIX", source, "MR", "MR");
            viewCode("STATE", source, "TX", "48");
        }

        tables.execute("DELETE FROM REF_PHN_AREA_CD WHERE NOTES = :m", Map.of("m", MARKER));
        for (var npa : List.of("512", "214", "713", "210", "817")) {
            tables.insert("REF_PHN_AREA_CD", row("NPA_ID", npa, "COUNTRY", "US", "IN_SERVICE", "Y", "NOTES", MARKER));
        }
        tables.insert("REF_PHN_AREA_CD", row("NPA_ID", "800", "SERVICE", "Toll-Free", "IN_SERVICE", "Y",
                "NOTES", MARKER));

        tables.deleteMarked("REF_JUNK_NAME_LIST", "NOTES");
        tables.insert("REF_JUNK_NAME_LIST", row("NAME", "UNKNOWN", "NOTES", MARKER));
        tables.insert("REF_JUNK_NAME_LIST", row("NAME", "BABY", "EDIT_LIMITATION", "FIRST", "NOTES", MARKER));

        tables.deleteRange("STG_TRS_CD_REF", "REF_ID", 990000, 990999);
        tables.insert("STG_TRS_CD_REF", row("REF_ID", 990001, "TABLENAME", "STREET_TYPE", "CODE", "ST",
                "DESCRIPTION", "St"));
        tables.insert("STG_TRS_CD_REF", row("REF_ID", 990002, "TABLENAME", "STREET_TYPE", "CODE", "AV",
                "DESCRIPTION", "Ave"));
    }

    private void codeValue(String type, String source, String sourceValue, String master, String label) {
        tables.insert("LOOKUP_CODE_VALUE", row("CREATED_BY", MARKER, "CREATE_DATE", LocalDateTime.now(),
                "CODE_TYPE", type, "SRC_SYS", source, "SRC_CODE_VALUE", sourceValue, "MSTR_REF_CODE", master,
                "MSTR_REF_LABEL", label));
    }

    /// `V_LOOKUP_CODE_VALUE` has no marker column: the exact seeded row is deleted before it is inserted again.
    private void viewCode(String type, String source, String sourceValue, String master) {
        tables.execute("""
                DELETE FROM V_LOOKUP_CODE_VALUE
                WHERE CODE_TYPE = :t AND SRC_SYS = :s AND SRC_CODE_VALUE = :v AND MSTR_CODE_VALUE = :m
                """, Map.of("t", type, "s", source, "v", sourceValue, "m", master));
        tables.insert("V_LOOKUP_CODE_VALUE", row("CODE_TYPE", type, "SRC_SYS", source, "SRC_CODE_VALUE",
                sourceValue, "MSTR_CODE_VALUE", master));
    }
}
