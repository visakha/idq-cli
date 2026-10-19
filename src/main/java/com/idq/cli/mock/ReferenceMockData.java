package com.idq.cli.mock;

import static com.idq.cli.core.EntityBuilder.entity;
import static com.idq.cli.mock.MockTables.MARKER;

import com.idq.cli.core.reference.ReferenceTables.AreaCode;
import com.idq.cli.core.reference.ReferenceTables.CodeValue;
import com.idq.cli.core.reference.ReferenceTables.ExceptionCode;
import com.idq.cli.core.reference.ReferenceTables.JunkName;
import com.idq.cli.core.reference.ReferenceTables.MasterCodeValue;
import com.idq.cli.source.trs.TrsSources.CdRef;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/// Seeds the shared lookup tables with the codes the mock source rows use: code translations, exception catalog,
/// area codes, junk names and TIERS street types. Seeded rows carry the mock marker and are replaced on every call.
/// Reference data never gets the `mock-data-pre-fix`.
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
        exceptionCatalog();
        codeValues();
        masterCodeValues();
        areaCodes();
        junkNames();
        streetTypes();
    }

    private void exceptionCatalog() {
        var now = LocalDateTime.now();
        tables.deleteMarked("EXC_LOOKUP_CODE_VALUE", "CREATED_BY");
        for (int i = 0; i < EXCEPTIONS.size(); i++) {
            var code = EXCEPTIONS.get(i);
            tables.insert(entity(ExceptionCode.class)
                    .with(ExceptionCode::excLookupCodeValueId, 990_000L + i)
                    .with(ExceptionCode::createdBy, MARKER)
                    .with(ExceptionCode::createDate, now)
                    .with(ExceptionCode::exceptionCode, code)
                    .with(ExceptionCode::exceptionDesc, code.replace('_', ' '))
                    .with(ExceptionCode::exceptionType, "Bad Value"));
        }
    }

    private void codeValues() {
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
    }

    private void areaCodes() {
        tables.execute("DELETE FROM REF_PHN_AREA_CD WHERE NOTES = :m", Map.of("m", MARKER));
        for (var npa : List.of("512", "214", "713", "210", "817")) {
            tables.insert(entity(AreaCode.class)
                    .with(AreaCode::npaId, npa)
                    .with(AreaCode::country, "US")
                    .with(AreaCode::inService, "Y")
                    .with(AreaCode::notes, MARKER));
        }
        tables.insert(entity(AreaCode.class)
                .with(AreaCode::npaId, "800")
                .with(AreaCode::service, "Toll-Free")
                .with(AreaCode::inService, "Y")
                .with(AreaCode::notes, MARKER));
    }

    private void junkNames() {
        tables.deleteMarked("REF_JUNK_NAME_LIST", "NOTES");
        tables.insert(entity(JunkName.class)
                .with(JunkName::name, "UNKNOWN")
                .with(JunkName::notes, MARKER));
        tables.insert(entity(JunkName.class)
                .with(JunkName::name, "BABY")
                .with(JunkName::editLimitation, "FIRST")
                .with(JunkName::notes, MARKER));
    }

    private void streetTypes() {
        tables.deleteRange("STG_TRS_CD_REF", "REF_ID", 990000, 990999);
        streetType(990_001L, "ST", "St");
        streetType(990_002L, "AV", "Ave");
    }

    private void codeValue(String type, String source, String sourceValue, String master, String label) {
        tables.insert(entity(CodeValue.class)
                .with(CodeValue::createdBy, MARKER)
                .with(CodeValue::createDate, LocalDateTime.now())
                .with(CodeValue::key, new CodeValue.Key(type, sourceValue, source))
                .with(CodeValue::mstrRefCode, master)
                .with(CodeValue::mstrRefLabel, label));
    }

    /// `V_LOOKUP_CODE_VALUE` has no marker column: the exact seeded row is deleted before it is inserted again.
    private void masterCode(String type, String source, String sourceValue, String master) {
        tables.execute("""
                DELETE FROM V_LOOKUP_CODE_VALUE
                WHERE CODE_TYPE = :t AND SRC_SYS = :s AND SRC_CODE_VALUE = :v AND MSTR_CODE_VALUE = :m
                """, Map.of("t", type, "s", source, "v", sourceValue, "m", master));
        tables.insert(entity(MasterCodeValue.class)
                .with(MasterCodeValue::codeType, type)
                .with(MasterCodeValue::srcSys, source)
                .with(MasterCodeValue::srcCodeValue, sourceValue)
                .with(MasterCodeValue::mstrCodeValue, master));
    }

    private void streetType(long id, String code, String description) {
        tables.insert(entity(CdRef.class)
                .with(CdRef::refId, id)
                .with(CdRef::tablename, "STREET_TYPE")
                .with(CdRef::code, code)
                .with(CdRef::description, description));
    }
}
