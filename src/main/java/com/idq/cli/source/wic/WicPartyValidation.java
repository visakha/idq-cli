package com.idq.cli.source.wic;

import static com.idq.cli.core.EtlPatterns.badData4Name;
import static com.idq.cli.core.EtlPatterns.missingNameCode;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.wic.WicQueries.ClientName;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_WIC_Pty_Validation` - decides which WIC clients are (de)activated.
/// See [docs/mappings/029_m_Tgt_C_S_WIC_Pty_Validation.md].
@Component
public class WicPartyValidation extends SourceMapping<ClientName, WicPartyValidation.Lookups>
        implements MemberMapping.Demographics<ClientName, WicPartyValidation.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("029", "m_Tgt_C_S_WIC_Pty_Validation", SourceSystem.WIC,
            List.of("STG_WIC_PTY_INACTIVE_STS", "STG_WIC_PTY_INACTIVE_LOG"), List.of(WicSources.EtlSrc.class,
            MdmBaseTables.PartyXref.class, WicTargets.InactiveStatus.class));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates) {}

    public WicPartyValidation(WicQueries queries) {
        super(INFO, queries::fetchClientNames, () -> new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())),
                LookupRows.toNumberMap(queries.fetchHubStates())));
    }

    /// A missing first or last name deactivates the client; a deactivated client with both names is reactivated.
    @Override
    public MappingOutput transform(List<ClientName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("WIC", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = r.ptySrcKey();
            var name = NameStandardization.standardize(new NameStandardization.Input(r.firstName(), r.middleName(),
                    r.lastName(), Infa.fullName(r.firstName(), r.middleName(), r.lastName()), null, null, "WIC"), ctx);
            var status = lookups.inactive().status(key);
            if (missingNameCode(name.first(), name.last()) != null) {
                bad.add(badData4Name(ctx, key, name.first(), name.middle(), name.last(), r.dob(), r.datekey(),
                        Infa.isMissing(name.first()) ? name.first() : name.last()));
                changes.deactivate(key, lookups.hubStates().get(key), status);
            } else if (status.isPresent()) {
                changes.reactivate(key);
            }
        }
        return InactiveStatus.output(changes, bad, WicTargets.InactiveStatus.class, WicTargets.InactiveStatus::new,
                WicTargets.InactiveLog.class, WicTargets.InactiveLog::new);
    }
}
