package com.idq.cli;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.reference.ReferenceSnapshot;
import com.idq.cli.domain.MappingInfo;
import java.lang.reflect.Proxy;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/// Shared fixtures for the PKEY tests: a fixed run time, seeded reference data and query stubs.
public final class Fixtures {

    public static final LocalDateTime RUN = LocalDateTime.of(2026, 10, 19, 6, 0);
    public static final LocalDateTime DAY = LocalDateTime.of(2026, 1, 15, 10, 30);

    private Fixtures() {}

    /// Lookup content used by the tests (codes deliberately different from source codes).
    public static ReferenceSnapshot reference() {
        var ref = ReferenceSnapshot.empty()
                .withCodeValue("TOA", "TRS", "A1", "100", "TOA 100")
                .withCodeValue("PHN_USG_TP", "TRS", "001", "001", "Main")
                .withCodeValue("ALT_ID_TP", "TRS", "002", "002", "Medicaid")
                .withCodeValue("ALT_ID_TP", "TRS", "004", "004", "SSN")
                .withCodeValue("ALT_ID_TP", "TRS", "007", "007", "Member id")
                .withCodeValue("REL_TP", "ECI", "1", "MTH", "Mother")
                .withCodeValue("REL_TP", "FSS", "MOTHER|F", "MTH", "Mother")
                .withMasterCode("PLAN_CD", "MAX", "PA", "PLN1")
                .withMasterCode("PTY_REL", "TRS", "PA", "PAR")
                .withMasterCode("ADDR_TP", "TRS", "MA", "002")
                .withMasterCode("ADDR_TP", "ECI", "1", "002")
                .withAreaCode("512", null)
                .withAreaCode("214", null)
                .withAreaCode("713", null)
                .withStreetType("ST", "St");
        for (var src : List.of("TRS", "ECI", "FSS", "TTF", "WIC")) {
            ref.withMasterCode("RACE", src, "W", "001").withMasterCode("ETHNICITY", src, "H", "1")
                    .withMasterCode("LANGUAGE_CD", src, "ENG", "EN");
        }
        return ref;
    }

    public static EtlContext ctx(MappingInfo info) {
        return new EtlContext(info, RUN, reference());
    }

    public static InactiveStatus.Lookup noInactive() {
        return InactiveStatus.Lookup.NONE;
    }

    public static InactiveStatus.Lookup inactive(String srcKey) {
        return new InactiveStatus.Lookup(Map.of(srcKey, "P"));
    }

    /// A named-query interface whose methods all return empty lists; the PKEY tests never read the database.
    @SuppressWarnings("unchecked")
    public static <T> T queries(Class<T> type) {
        return (T) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] {type},
                (proxy, method, args) -> List.of());
    }
}
