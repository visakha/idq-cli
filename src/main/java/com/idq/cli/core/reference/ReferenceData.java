package com.idq.cli.core.reference;

import java.util.Optional;

/// The shared lookup tables used by the mappings and mapplets. Every IDQ lookup uses "return any row" on
/// duplicates, so implementations keep the first row found per key.
public interface ReferenceData {

    /// `LOOKUP_CODE_VALUE` matched on `CODE_TYPE`, `SRC_SYS`, `SRC_CODE_VALUE`; a `null` code type matches any type
    /// (as in the CRE `lkp_ALT_ID_MSTR_REF_CODE`, which filters on the source system only).
    Optional<CodeValue> codeValue(String codeType, String srcSys, String srcCodeValue);

    /// `LOOKUP_CODE_VALUE` matched on `CODE_TYPE`, `SRC_SYS`, `MSTR_REF_CODE` (used for label lookups).
    Optional<CodeValue> codeValueByMaster(String codeType, String srcSys, String mstrRefCode);

    /// `LOOKUP_CODE_VALUE` matched on `CODE_TYPE` and `MSTR_REF_LABEL`, any source system (the TOA catalogue,
    /// `m_Tgt_C_S_TRS_Stg_TOA`, translates TIERS codes by label).
    Optional<CodeValue> codeValueByLabel(String codeType, String mstrRefLabel);

    /// `V_LOOKUP_CODE_VALUE.MSTR_CODE_VALUE` matched on `CODE_TYPE`, `SRC_SYS`, `SRC_CODE_VALUE`;
    /// a `null` code type matches any type (as in `rule_Suffix_Std`, which has no type filter).
    Optional<String> masterCode(String codeType, String srcSys, String srcCodeValue);

    /// `EXC_LOOKUP_CODE_VALUE` description and type for an exception code.
    ExceptionInfo exception(String code);

    /// `REF_PHN_AREA_CD` rows that are in service, US or non-geographic, and geographic or toll free.
    Optional<AreaCode> areaCode(String npa);

    /// `REF_JUNK_NAME_LIST` with `EDIT_LIMITATION` null or `FIRST` / `LAST`.
    boolean isJunkFirstName(String upperName);

    boolean isJunkLastName(String upperName);

    /// `STG_TRS_CD_REF.DESCRIPTION` for a TIERS street type code.
    Optional<String> streetTypeDescription(String code);

    record CodeValue(String mstrRefCode, String mstrRefLabel) {}

    record AreaCode(String npa, String service) {}
}
