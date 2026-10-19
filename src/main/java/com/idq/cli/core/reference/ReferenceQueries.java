package com.idq.cli.core.reference;

import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.relational.core.mapping.Table;
import org.springframework.data.repository.Repository;

/// Native queries that load the shared lookup tables into a [ReferenceSnapshot].
public interface ReferenceQueries extends Repository<ReferenceQueries.LookupCodeValue, String> {

    @Table("LOOKUP_CODE_VALUE")
    record LookupCodeValue(String codeType, String srcSys, @Id String srcCodeValue, String mstrRefCode,
            String mstrRefLabel) {}

    record ViewCodeValue(String codeType, String srcSys, String srcCodeValue, String mstrCodeValue) {}

    record ExceptionCode(String exceptionCode, String exceptionDesc, String exceptionType) {}

    record AreaCodeRow(String npaId, String service) {}

    record JunkName(String name, String editLimitation) {}

    record StreetType(String code, String description) {}

    @Query("SELECT CODE_TYPE, SRC_SYS, SRC_CODE_VALUE, MSTR_REF_CODE, MSTR_REF_LABEL FROM LOOKUP_CODE_VALUE")
    List<LookupCodeValue> lookupCodeValues();

    @Query("SELECT CODE_TYPE, SRC_SYS, SRC_CODE_VALUE, MSTR_CODE_VALUE FROM V_LOOKUP_CODE_VALUE")
    List<ViewCodeValue> viewCodeValues();

    @Query("SELECT EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE FROM EXC_LOOKUP_CODE_VALUE")
    List<ExceptionCode> exceptionCodes();

    /// `Lookup_REF_PHN_AREA_CD` filter of `rule_Phone_Std` (Snowflake `current_date()` becomes `SYSDATE`).
    @Query("""
            SELECT NPA_ID, SERVICE
            FROM REF_PHN_AREA_CD
            WHERE (IN_SERVICE = 'Y' OR SYSDATE >= IN_SERVICE_DT)
              AND (SERVICE IS NULL OR SERVICE = 'Toll-Free')
              AND (COUNTRY = 'US' OR COUNTRY IS NULL)
            """)
    List<AreaCodeRow> areaCodes();

    @Query("SELECT NAME, EDIT_LIMITATION FROM REF_JUNK_NAME_LIST")
    List<JunkName> junkNames();

    @Query("SELECT CODE, DESCRIPTION FROM STG_TRS_CD_REF")
    List<StreetType> streetTypes();
}
