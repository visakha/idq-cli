package com.idq.cli.source.fss;

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
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.fss.FssQueries.ClientName;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_FSS_Pty_Validation` - decides which FSS clients are (de)activated.
/// See [docs/mappings/019_m_Tgt_C_S_FSS_Pty_Validation.md].
@Component
public class FssPartyValidation extends SourceMapping<ClientName, FssPartyValidation.Lookups>
        implements MemberMapping.Demographics<ClientName, FssPartyValidation.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("019", "m_Tgt_C_S_FSS_Pty_Validation", SourceSystem.FSS,
            List.of("STG_FSS_PTY_INACTIVE_STS", "STG_FSS_PTY_INACTIVE_LOG"), List.of(FssSources.EtlSrc.class,
            MdmBaseTables.PartyXref.class, FssTargets.InactiveStatus.class));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates) {}

    public FssPartyValidation(FssQueries queries) {
        super(INFO, queries::fetchClientNames, () -> new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())),
                LookupRows.toNumberMap(queries.fetchHubStates())));
    }

    /// Deactivate on a missing name, a deleted client (`CLIENT_DTL__CAPXACTION = 'D'`) or when every registration
    /// is inactive. Reactivate a deactivated client that is complete again.
    ///
    /// As in IDQ, the reactivation is written into `STG_FSS_PTY_INACTIVE_STS` with status `Reactivation` (not into
    /// the log) after the old status row is deleted - see the mapping document.
    @Override
    public MappingOutput transform(List<ClientName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("FSS", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = r.ptySrcKey();
            var name = NameStandardization.standardize(new NameStandardization.Input(r.nmFirst(), r.nmMiddle(),
                    r.nmLast(), Infa.fullName(r.nmFirst(), r.nmMiddle(), r.nmLast()), null, null, "FSS"), ctx);
            var status = lookups.inactive().status(key);
            boolean nameMissing = missingNameCode(name.first(), name.last()) != null;
            if (nameMissing) {
                bad.add(badData4Name(ctx, key, name.first(), name.middle(), name.last(), r.dtDob(), r.dtLastUpdate(),
                        name.srcFull()));
            }
            if (nameMissing || "D".equals(r.clientDtlCapxaction()) || "Y".equals(r.lastInactvClientYn())) {
                changes.deactivate(key, lookups.hubStates().get(key), status);
            }
            if (status.isPresent() && hasLength(name.first()) && hasLength(name.last())
                    && r.clientDtlCapxaction() != null && !"D".equals(r.clientDtlCapxaction())
                    && r.lastInactvClientYn() != null && !"Y".equals(r.lastInactvClientYn())) {
                changes.reactivate(key);
            }
        }
        var reactivations = changes.logs.stream().filter(l -> l.action().equals("Reactivation"))
                .map(l -> new FssTargets.InactiveStatus(l.srcKey(), l.rowidSystem(), l.action(), l.actionDt()))
                .toList();
        changes.logs.removeIf(l -> l.action().equals("Reactivation"));
        return InactiveStatus.output(changes, bad, FssTargets.InactiveStatus.class, FssTargets.InactiveStatus::new,
                FssTargets.InactiveLog.class, FssTargets.InactiveLog::new)
                .load(TargetBatch.append(FssTargets.InactiveStatus.class, reactivations));
    }

    static boolean hasLength(String value) {
        return value != null && !value.stripTrailing().isEmpty();
    }
}
