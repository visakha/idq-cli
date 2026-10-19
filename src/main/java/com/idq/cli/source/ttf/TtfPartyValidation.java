package com.idq.cli.source.ttf;

import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.isMissing;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.trim;
import static com.idq.cli.core.Infa.upper;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.ttf.TtfQueries.ClientName;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TTF_Pty_Validation` - decides which TTF clients are (de)activated.
/// See [docs/mappings/025_m_Tgt_C_S_TTF_Pty_Validation.md].
@Component
public class TtfPartyValidation extends SourceMapping<ClientName, TtfPartyValidation.Lookups>
        implements MemberMapping.Demographics<ClientName, TtfPartyValidation.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("025", "m_Tgt_C_S_TTF_Pty_Validation", SourceSystem.TTF,
            List.of("STG_TTF_PTY_INACTIVE_STS", "STG_TTF_PTY_INACTIVE_LOG"),
            List.of("V_TTF_ETL_SRC", "C_B_PTY_XREF", "STG_TTF_PTY_INACTIVE_STS"));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates) {}

    public TtfPartyValidation(TtfQueries queries) {
        super(INFO, queries::fetchClientNames, () -> new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())),
                LookupRows.toNumberMap(queries.fetchHubStates())));
    }

    public static String partyKey(Long clientsId) {
        return lpad(clientsId, 10, '0');
    }

    static boolean declined(String name) {
        return in(upper(name), "DECLINED");
    }

    static boolean withheld(String name) {
        return in(upper(name), "DECLINED", "DO_NOT_DISCLOSE");
    }

    /// `Missing_First_Name`, `Invalid_First_Name` (declined / not disclosed), then the same for the last name.
    public static String nameExceptionCode(String first, String last) {
        if (isMissing(first)) {
            return "Missing_First_Name";
        }
        if (in(upper(trim(first)), "DECLINED", "DO_NOT_DISCLOSE")) {
            return "Invalid_First_Name";
        }
        if (isMissing(last)) {
            return "Missing_Last_Name";
        }
        return in(upper(trim(last)), "DECLINED", "DO_NOT_DISCLOSE") ? "Invalid_Last_Name" : "Valid";
    }

    @Override
    public MappingOutput transform(List<ClientName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("TTF", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = partyKey(r.clientsId());
            var name = NameStandardization.standardize(new NameStandardization.Input(r.firstname(), r.middlename(),
                    r.lastname(), Infa.fullName(r.firstname(), r.middlename(), r.lastname()), null, null, "TTF"),
                    ctx);
            var first = name.first();
            var last = name.last();
            var status = lookups.inactive().status(key);
            boolean missing = isMissing(first) || isMissing(last);
            if (missing || withheld(first) || withheld(last)) {
                var code = nameExceptionCode(first, last);
                bad.add(ctx.badRecord().ids(key, null, null).exception(ctx.exception(code))
                        .attribute(code, name.srcFull()).name(null, first, name.middle(), last, null)
                        .person(r.dob(), null, null).build());
            }
            if (missing || declined(first) || declined(last) || "N".equals(r.clientExistsFlag())) {
                changes.deactivate(key, lookups.hubStates().get(key), status);
            }
            if (status.isPresent() && !missing && !declined(first) && !declined(last)
                    && "Y".equals(r.clientExistsFlag())) {
                changes.reactivate(key);
            }
        }
        return InactiveStatus.output(changes, bad, TtfTargets.InactiveStatus.class, TtfTargets.InactiveStatus::new,
                TtfTargets.InactiveLog.class, TtfTargets.InactiveLog::new);
    }
}
