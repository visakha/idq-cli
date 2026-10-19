package com.idq.cli.source.eci;

import static com.idq.cli.core.EtlPatterns.memberRole;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.EtlPatterns;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.PartyPattern;
import com.idq.cli.core.PartyPattern.Check;
import com.idq.cli.core.PartyPattern.RaceSource;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.eci.EciQueries.PartyDemographics;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_ECI_Pty` - child and family demographics plus member role. See [docs/mappings/014_m_Tgt_C_S_ECI_Pty.md].
@Component
public class EciParty extends SourceMapping<PartyDemographics, InactiveStatus.Lookup>
        implements MemberMapping.Demographics<PartyDemographics, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("014", "m_Tgt_C_S_ECI_Pty", SourceSystem.ECI,
            List.of("C_S_ECI_PTY", "C_S_ECI_PTY_RLE"), List.of(EciSources.DChild.class, EciSources.DFamily.class,
            EciTargets.InactiveStatus.class));

    /// Ethnicity, race and language exceptions are only raised for children.
    static final PartyPattern.Spec SPEC = new PartyPattern.Spec("ECI", RaceSource.INDICATORS, true, false,
            Set.of(Check.ETHNICITY, Check.RACE, Check.LANGUAGE));

    public EciParty(EciQueries queries) {
        super(INFO, queries::fetchPartyDemographics,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    @Override
    public MappingOutput transform(List<PartyDemographics> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var parties = new ArrayList<EciTargets.Party>();
        var roles = new ArrayList<EciTargets.PartyRole>();
        var bad = new ArrayList<com.idq.cli.core.exception.BadRecord>();
        for (var r : rows) {
            var key = EciPartyValidation.partyKey(r.sourceTable(), r.id()).strip();
            if (!inactive.isActive(key)) {
                continue;
            }
            var v = PartyPattern.apply(SPEC, new PartyPattern.Input(key, r.id(), "ECI_CHILD".equals(r.sourceTable()),
                    r.firstName(), r.middleInitial(), r.lastName(), null, r.dob(), r.gender(), r.ethnicity(),
                    r.languageCd(), r.raceCd(), r.raceWhite(), r.raceAa(), r.raceAsian(), r.racePi(), r.raceAn(),
                    r.dateCreated()), ctx);
            bad.addAll(v.exceptions());
            var audit = MdmAudit.srcRowid(key).periodStart(r.dateModified()).lastUpdated(ctx.runStart())
                    .created(r.dateCreated()).by(r.createdBy(), r.modifiedBy()).hubState(1)
                    .sourceUpdated(r.dateModified());
            parties.add(new EciTargets.Party(key, audit, new Columns.Party("Indv", v.name().prefix(),
                    v.name().first(), v.name().middle(), v.name().last(), null, v.name().full(), v.gender().value(),
                    v.birth().value(), null, v.name().srcFull(), v.ethnicity().value(), r.ethnicity(), v.mdmRaceCd(),
                    v.srcRaceCd()), birthWeightGrams(r.birthWtLb(), r.birthWtOz()), v.language().value(),
                    r.languageCd()));
            var roleKey = memberRole(key);
            roles.add(new EciTargets.PartyRole(roleKey, MdmAudit.srcRowid(roleKey).periodStart(r.dateCreated())
                    .lastUpdated(ctx.runStart()).created(r.dateCreated()).by(r.createdBy(), null).hubState(1)
                    .sourceUpdated(r.dateModified()), new Columns.PartyRole(key, EtlPatterns.MEMBER)));
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(EciTargets.Party.class,
                        Rows.lastPerKey(parties, EciTargets.Party::pkeySrcObject)))
                .load(TargetBatch.replaceAll(EciTargets.PartyRole.class,
                        Rows.lastPerKey(roles, EciTargets.PartyRole::pkeySrcObject)))
                .reject(bad);
    }

    /// `BIRTH_WT_LB * 453.6 + BIRTH_WT_OZ * 28.35`
    public static BigDecimal birthWeightGrams(BigDecimal pounds, BigDecimal ounces) {
        return pounds == null || ounces == null ? null
                : pounds.multiply(new BigDecimal("453.6")).add(ounces.multiply(new BigDecimal("28.35")));
    }
}
