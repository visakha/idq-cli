package com.idq.cli.source.ttf;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.EtlPatterns;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.PartyPattern;
import com.idq.cli.core.PartyPattern.RaceSource;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.ttf.TtfQueries.ClientDemographics;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TTF_Pty` - client demographics and member role. See [docs/mappings/026_m_Tgt_C_S_TTF_Pty.md].
@Component
public class TtfParty extends SourceMapping<ClientDemographics, InactiveStatus.Lookup>
        implements MemberMapping.Demographics<ClientDemographics, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("026", "m_Tgt_C_S_TTF_Pty", SourceSystem.TTF,
            List.of("C_S_TTF_PTY", "C_S_TTF_PTY_RLE"), List.of(TtfSources.EtlSrc.class,
            TtfTargets.InactiveStatus.class));

    /// Race by code (`RACE` lookup); no language or suffix rule; every exception applies to every row.
    static final PartyPattern.Spec SPEC = new PartyPattern.Spec("TTF", RaceSource.CODE, false, false, Set.of());

    public TtfParty(TtfQueries queries) {
        super(INFO, queries::fetchClientDemographics,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    /// `SEXID` 33 is female, 34 male, anything else unknown.
    public static String gender(String sexId) {
        return switch (sexId == null ? "" : sexId) {
            case "33" -> "F";
            case "34" -> "M";
            default -> "U";
        };
    }

    /// Ethnicity is only known through the combined race / ethnicity code `55`.
    public static String ethnicity(String raceEthnicityId) {
        return "55".equals(raceEthnicityId) ? "55" : null;
    }

    @Override
    public MappingOutput transform(List<ClientDemographics> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var parties = new ArrayList<TtfTargets.Party>();
        var roles = new ArrayList<TtfTargets.PartyRole>();
        var bad = new ArrayList<BadRecord>();
        for (var r : Rows.where(rows, r -> inactive.isActive(r.ptySrcKey()))) {
            var key = trim(r.ptySrcKey());
            var gender = gender(r.sexid());
            var ethnicity = ethnicity(r.raceethnicityid());
            var v = PartyPattern.apply(SPEC, new PartyPattern.Input(key, r.clientsId(), true, r.firstname(),
                    r.middlename(), r.lastname(), null, r.dob(), gender, ethnicity, null, r.raceethnicityid(), null,
                    null, null, null, null, r.submitdate()), ctx);
            bad.addAll(v.exceptions());
            var audit = MdmAudit.srcRowid(key).periodStart(ctx.runStart()).lastUpdated(ctx.runStart())
                    .created(r.submitdate()).hubState(1).sourceUpdated(r.submitdate());
            parties.add(new TtfTargets.Party(key, audit, new Columns.Party("Indv", v.name().prefix(),
                    v.name().first(), v.name().middle(), v.name().last(), null, v.name().full(), v.gender().value(),
                    v.birth().value(), null, v.name().srcFull(), v.ethnicity().value(), ethnicity, v.mdmRaceCd(),
                    null), null));
            var roleKey = memberRole(key);
            roles.add(new TtfTargets.PartyRole(roleKey, audit.withSrcRowid(roleKey).periodStart(r.submitdate()),
                    new Columns.PartyRole(key, EtlPatterns.MEMBER)));
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(TtfTargets.Party.class,
                        Rows.lastPerKey(parties, TtfTargets.Party::pkeySrcObject)))
                .load(TargetBatch.replaceAll(TtfTargets.PartyRole.class,
                        Rows.lastPerKey(roles, TtfTargets.PartyRole::pkeySrcObject)))
                .reject(bad);
    }
}
