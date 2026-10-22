package com.idq.cli.mock;

import static com.idq.cli.mock.MockTables.MARKER;

import com.idq.cli.core.reference.ReferenceTables.AreaCode;
import com.idq.cli.core.reference.ReferenceTables.CodeValue;
import com.idq.cli.core.reference.ReferenceTables.ExceptionCode;
import com.idq.cli.core.reference.ReferenceTables.JunkName;
import com.idq.cli.core.reference.ReferenceTables.MasterCodeValue;
import com.idq.cli.source.trs.etldb.models.TrsSources.CdRef;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/// Seeds the shared lookup tables with the codes the mock source rows use: code translations, exception catalog,
/// area codes, junk names and TIERS street types. Seeded rows carry the mock marker and are replaced on every call.
/// Reference data never gets the `mock-data-pre-fix`.
@Component
public class ReferenceMockData {

    static final List<String> SOURCES = List.of("TRS", "ECI", "FSS", "TTF", "WIC", "CRE");

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
        exceptionCatalog();
        codeValues();
        masterCodeValues();
        areaCodes();
        junkNames();
        streetTypes();
    }

    private void exceptionCatalog() {
        var now = LocalDateTime.now();
        tables.skipIfMarked("EXC_LOOKUP_CODE_VALUE", "CREATED_BY");
        for (int i = 0; i < EXCEPTIONS.size(); i++) {
            var code = EXCEPTIONS.get(i);
            tables.insert(ExceptionCode.builder()
                    .excLookupCodeValueId(990_000L + i)
                    .createdBy(MARKER)
                    .createDate(now)
                    .exceptionCode(code)
                    .exceptionDesc(code.replace('_', ' '))
                    .exceptionType("Bad Value")
                    .build());
        }
    }

    private void codeValues() {
        tables.skipIfMarked("LOOKUP_CODE_VALUE", "CREATED_BY");
        codeValue("TOA", "TRS", "A1", "100", "Medicaid TOA 100");
        codeValue("TOA", "TRS", "B2", "200", "Medicaid TOA 200");
        for (var usage : List.of("001", "002", "003")) {
            codeValue("PHN_USG_TP", "TRS", usage, usage, "Usage " + usage);
        }
        for (var type : List.of("002", "004", "007")) {
            codeValue("ALT_ID_TP", "TRS", type, type, "Alternate id " + type);
        }
        // CRE translates the type names; 022 for the CARE id is a mock code (the real one is not in the exports)
        codeValue("ALT_ID_TP", "CRE", "CARE ID", "022", "CARE Id");
        codeValue("ALT_ID_TP", "CRE", "Medicaid ID", "002", "Medicaid Id");
        codeValue("ALT_ID_TP", "CRE", "SSN", "004", "SSN");
        codeValue("REL_TP", "ECI", "1", "MTH", "Mother");
        codeValue("INVERSE_REL", "ECI", "1|M", "SON", "Son");
        codeValue("INVERSE_REL", "ECI", "1|F", "DAU", "Daughter");
        codeValue("REL_TP", "FSS", "MOTHER|F", "MTH", "Mother");
        codeValue("INVERSE_REL", "FSS", "MOTHER|M", "SON", "Son");
        codeValue("INVERSE_REL", "FSS", "MOTHER|F", "DAU", "Daughter");
    }

    private void masterCodeValues() {
        masterCode("PLAN_CD", "MAX", "PA", "PLANA");
        masterCode("PTY_REL", "TRS", "PA", "PAR");
        masterCode("PTY_REL", "TRS", "CH", "CHL");
        masterCode("ADDR_TP", "TRS", "MA", "002");
        masterCode("ADDR_TP", "TRS", "PH", "001");
        masterCode("ADDR_TP", "ECI", "1", "002");
        for (var source : SOURCES) {
            masterCode("RACE", source, "W", "001");
            masterCode("ETHNICITY", source, "H", "1");
            masterCode("ETHNICITY", source, "1", "1");
            masterCode("ETHNICITY", source, "55", "1");
            masterCode("LANGUAGE_CD", source, "ENG", "EN");
            masterCode("LANGUAGE_CD", source, "1", "EN");
            masterCode("SUFFIX", source, "JR", "JR");
            masterCode("PREFIX", source, "MR", "MR");
            masterCode("STATE", source, "TX", "48");
        }
        // a CRE client abroad: the CRE state lookup has no code-type filter, 99 routes the address as non-US
        masterCode("STATE", "CRE", "FC", "99");
    }

    private void areaCodes() {
        tables.skipIf("REF_PHN_AREA_CD", "NOTES = :m", Map.of("m", MARKER));
        for (var npa : List.of("512", "214", "713", "210", "817")) {
            tables.insert(AreaCode.builder()
                    .npaId(npa)
                    .country("US")
                    .inService("Y")
                    .notes(MARKER)
                    .build());
        }
        tables.insert(AreaCode.builder()
                .npaId("800")
                .service("Toll-Free")
                .inService("Y")
                .notes(MARKER)
                .build());
    }

    private void junkNames() {
        tables.skipIfMarked("REF_JUNK_NAME_LIST", "NOTES");
        tables.insert(JunkName.builder()
                .name("UNKNOWN")
                .notes(MARKER)
                .build());
        tables.insert(JunkName.builder()
                .name("BABY")
                .editLimitation("FIRST")
                .notes(MARKER)
                .build());
    }

    private void streetTypes() {
        tables.skipIfPresent("STG_TRS_CD_REF", "REF_ID", 990000, 990999);
        streetType(990_001L, "ST", "St");
        streetType(990_002L, "AV", "Ave");
    }

    private void codeValue(String type, String source, String sourceValue, String master, String label) {
        tables.insert(CodeValue.builder()
                .createdBy(MARKER)
                .createDate(LocalDateTime.now())
                .key(new CodeValue.Key(type, sourceValue, source))
                .mstrRefCode(master)
                .mstrRefLabel(label)
                .build());
    }

    /// `V_LOOKUP_CODE_VALUE` has no marker column: the row is inserted only when that exact row is not there yet.
    private void masterCode(String type, String source, String sourceValue, String master) {
        if (tables.exists("V_LOOKUP_CODE_VALUE",
                "CODE_TYPE = :t AND SRC_SYS = :s AND SRC_CODE_VALUE = :v AND MSTR_CODE_VALUE = :m",
                Map.of("t", type, "s", source, "v", sourceValue, "m", master))) {
            return;
        }
        tables.insert(MasterCodeValue.builder()
                .codeType(type)
                .srcSys(source)
                .srcCodeValue(sourceValue)
                .mstrCodeValue(master)
                .build());
    }

    private void streetType(long id, String code, String description) {
        tables.insert(CdRef.builder()
                .refId(id)
                .tablename("STREET_TYPE")
                .code(code)
                .description(description)
                .build());
    }
}
