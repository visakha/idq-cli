package com.idq.cli.core.reference;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/// Immutable-after-load, in-memory [ReferenceData]: the equivalent of IDQ's cached lookups.
/// Built by [ReferenceLoader] from the database, or by hand in unit tests.
public final class ReferenceSnapshot implements ReferenceData {

    private final Map<String, CodeValue> codeValues = new HashMap<>();
    private final Map<String, CodeValue> codeValuesByMaster = new HashMap<>();
    private final Map<String, CodeValue> codeValuesByLabel = new HashMap<>();
    private final Map<String, String> masterCodes = new HashMap<>();
    private final Map<String, ExceptionInfo> exceptions = new HashMap<>();
    private final Map<String, AreaCode> areaCodes = new HashMap<>();
    private final Set<String> junkFirst = new HashSet<>();
    private final Set<String> junkLast = new HashSet<>();
    private final Map<String, String> streetTypes = new HashMap<>();

    public static ReferenceSnapshot empty() {
        return new ReferenceSnapshot();
    }

    public ReferenceSnapshot withCodeValue(String codeType, String srcSys, String srcValue, String mstrCode,
            String mstrLabel) {
        var value = new CodeValue(mstrCode, mstrLabel);
        codeValues.putIfAbsent(key(codeType, srcSys, srcValue), value);
        codeValues.putIfAbsent(key(null, srcSys, srcValue), value);
        codeValuesByMaster.putIfAbsent(key(codeType, srcSys, mstrCode), value);
        codeValuesByLabel.putIfAbsent(key(codeType, null, mstrLabel), value);
        return this;
    }

    public ReferenceSnapshot withMasterCode(String codeType, String srcSys, String srcValue, String mstrCode) {
        masterCodes.putIfAbsent(key(codeType, srcSys, srcValue), mstrCode);
        masterCodes.putIfAbsent(key(null, srcSys, srcValue), mstrCode);
        return this;
    }

    public ReferenceSnapshot withException(String code, String description, String type) {
        exceptions.putIfAbsent(code, new ExceptionInfo(code, description, type));
        return this;
    }

    public ReferenceSnapshot withAreaCode(String npa, String service) {
        areaCodes.putIfAbsent(npa, new AreaCode(npa, service));
        return this;
    }

    public ReferenceSnapshot withJunkName(String upperName, String editLimitation) {
        if (editLimitation == null || "FIRST".equals(editLimitation)) {
            junkFirst.add(upperName);
        }
        if (editLimitation == null || "LAST".equals(editLimitation)) {
            junkLast.add(upperName);
        }
        return this;
    }

    public ReferenceSnapshot withStreetType(String code, String description) {
        streetTypes.putIfAbsent(code, description);
        return this;
    }

    @Override
    public Optional<CodeValue> codeValue(String codeType, String srcSys, String srcCodeValue) {
        return Optional.ofNullable(codeValues.get(key(codeType, srcSys, srcCodeValue)));
    }

    @Override
    public Optional<CodeValue> codeValueByMaster(String codeType, String srcSys, String mstrRefCode) {
        return Optional.ofNullable(codeValuesByMaster.get(key(codeType, srcSys, mstrRefCode)));
    }

    @Override
    public Optional<CodeValue> codeValueByLabel(String codeType, String mstrRefLabel) {
        return Optional.ofNullable(codeValuesByLabel.get(key(codeType, null, mstrRefLabel)));
    }

    @Override
    public Optional<String> masterCode(String codeType, String srcSys, String srcCodeValue) {
        return Optional.ofNullable(masterCodes.get(key(codeType, srcSys, srcCodeValue)));
    }

    @Override
    public ExceptionInfo exception(String code) {
        return exceptions.getOrDefault(code, new ExceptionInfo(code, null, null));
    }

    @Override
    public Optional<AreaCode> areaCode(String npa) {
        return Optional.ofNullable(areaCodes.get(npa));
    }

    @Override
    public boolean isJunkFirstName(String upperName) {
        return junkFirst.contains(upperName);
    }

    @Override
    public boolean isJunkLastName(String upperName) {
        return junkLast.contains(upperName);
    }

    @Override
    public Optional<String> streetTypeDescription(String code) {
        return Optional.ofNullable(streetTypes.get(code));
    }

    private static String key(String codeType, String srcSys, String value) {
        return codeType + "\u0000" + srcSys + "\u0000" + value;
    }
}
