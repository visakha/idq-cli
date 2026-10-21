package com.idq.cli.source.trs;

import static com.idq.cli.core.EtlPatterns.badData4BirthDate;
import static com.idq.cli.core.EtlPatterns.badData4Code;
import static com.idq.cli.core.EtlPatterns.badData4DeathDate;
import static com.idq.cli.core.EtlPatterns.badData4Gender;
import static com.idq.cli.core.EtlPatterns.badData4Name;
import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.missingNameCode;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.toChar;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.EtlPatterns;
import com.idq.cli.core.EtlPatterns.PersonName;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.core.rules.PersonRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.MemberDemographics;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_OnGoing` - member demographics, member role and the valid-member registry.
/// See [docs/mappings/001_m_Tgt_C_S_TRS_Pty_OnGoing.md].
@Component
public class TrsPartyOnGoing extends SourceMapping<MemberDemographics, TrsPartyOnGoing.Lookups>
        implements MemberMapping.Demographics<MemberDemographics, TrsPartyOnGoing.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("001", "m_Tgt_C_S_TRS_Pty_OnGoing", SourceSystem.TRS,
            List.of("C_S_TRS_PTY", "C_S_TRS_PTY_RLE", "STG_TRS_VALID_MEMBERS"), List.of(TrsSources.DcIndvDelta.class,
            TrsSources.CvDcMciIndvDelta.class, TrsSources.CvMciEdgIndvToaDelta.class, TrsTargets.ValidMember.class,
            TrsSources.DeactivedMembers.class));

    /// @param validMemberKeys `STG_TRS_VALID_MEMBERS.PTY_PK` before the run
    public record Lookups(Set<String> validMemberKeys) {}

    public TrsPartyOnGoing(TrsQueries queries) {
        super(INFO, queries::fetchMemberDemographics,
                () -> new Lookups(new HashSet<>(queries.fetchValidMemberKeys())));
    }

    /// `PKEY_SRC_OBJECT` of `C_S_TRS_PTY`: daily TIERS individuals carry the `|DC_INDV` suffix, MCI conversion
    /// individuals the bare individual id.
    public static String partyKey(Long indvId, String srcTbl) {
        return trim("DC_INDV".equals(srcTbl) ? pipe(indvId, "DC_INDV") : toChar(indvId));
    }

    /// A row after the demographic rules have run.
    record Validated(MemberDemographics src, String pkey, String srcFullName, NameStandardization.Output name,
            PersonRules.Checked<java.time.LocalDateTime> birth, PersonRules.Checked<String> gender,
            ExceptionInfo death) {

        PersonName personName() {
            return new PersonName(name.prefix(), name.first(), name.middle(), name.last(), name.suffix());
        }

        boolean validParty() {
            return name.first() != null || name.last() != null;
        }
    }

    @Override
    public MappingOutput transform(List<MemberDemographics> rows, Lookups lookups, EtlContext ctx) {
        var validated = rows.stream().map(row -> validate(row, ctx)).toList();
        var bad = new ArrayList<BadRecord>();
        validated.forEach(v -> bad.addAll(exceptions(v, ctx)));

        var validParties = Rows.lastPerKey(Rows.sorted(Rows.distinct(Rows.where(validated, Validated::validParty)),
                Rows.<Validated, String>asc(Validated::pkey).thenComparing(Rows.asc(v -> v.src().createDt()))),
                Validated::pkey);

        var parties = new ArrayList<TrsTargets.Party>();
        var roles = new ArrayList<TrsTargets.PartyRole>();
        for (var v : validParties) {
            var race = PersonRules.codeValue("RACE", "TRS", v.src().raceCd(), "Invalid_Race", ctx);
            var ethnicity = PersonRules.codeValue("ETHNICITY", "TRS", v.src().ethnicityCd(), "Invalid_Ethnicity", ctx);
            Stream.of(race.exception().configured() ? badData4Code(ctx, "Race_Cd", v.src().raceCd(), v.pkey(), null,
                            v.personName(), v.birth().value(), v.gender().value(), v.src().createDt(), race.exception())
                            : null,
                    ethnicity.exception().configured() ? badData4Code(ctx, "Ethnicity_Cd", v.src().ethnicityCd(),
                            v.pkey(), null, v.personName(), v.birth().value(), v.gender().value(), v.src().createDt(),
                            ethnicity.exception()) : null)
                    .filter(java.util.Objects::nonNull).forEach(bad::add);
            var audit = MdmAudit.srcRowid(v.pkey()).periodStart(v.src().createDt())
                    .lastUpdated(EtlPatterns.timeStampNow(ctx)).sourceUpdated(v.src().createDt());
            parties.add(new TrsTargets.Party(v.pkey(), audit, new Columns.Party("Indv", v.name().prefix(),
                    v.name().first(), v.name().middle(), v.name().last(), v.name().suffix(), v.name().full(),
                    v.gender().value(), v.birth().value(), null, v.srcFullName(), ethnicity.value(),
                    v.src().ethnicityCd(), race.value(), v.src().raceCd()), v.src().deathDt()));
            var roleKey = memberRole(v.pkey());
            roles.add(new TrsTargets.PartyRole(roleKey, MdmAudit.srcRowid(roleKey).periodStart(v.src().createDt())
                    .lastUpdated(ctx.runStart()).sourceUpdated(v.src().createDt()),
                    new Columns.PartyRole(v.pkey(), EtlPatterns.MEMBER)));
        }

        var newValidMembers = Rows.firstPerKey(Rows.where(validParties,
                        v -> !lookups.validMemberKeys().contains(v.pkey())), Validated::pkey).stream()
                .map(v -> new TrsTargets.ValidMember(v.src().indvId(), v.pkey(), v.src().srcTbl(), ctx.runStart()))
                .toList();

        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(TrsTargets.Party.class, parties))
                .load(TargetBatch.replaceAll(TrsTargets.PartyRole.class, roles))
                .load(TargetBatch.append(TrsTargets.ValidMember.class, newValidMembers))
                .reject(bad);
    }

    static Validated validate(MemberDemographics r, EtlContext ctx) {
        var fullName = Infa.fullName(r.firstName(), r.midName(), r.lastName());
        var name = NameStandardization.standardize(new NameStandardization.Input(r.firstName(), r.midName(),
                r.lastName(), fullName, r.prefixName(), r.sufxName(), "TRS"), ctx);
        var death = r.deathDt() != null && r.deathDt().isAfter(ctx.runStart())
                ? ctx.exception("Invalid_Death_Date") : ExceptionInfo.NONE;
        return new Validated(r, partyKey(r.indvId(), r.srcTbl()), fullName, name,
                PersonRules.birthDate(r.dobDt(), "Indv", "TRS", ctx),
                PersonRules.gender(r.genderCd(), "Indv", "TRS", ctx), death);
    }

    /// `rtr_Invalid_Party` exception groups. Gender and death date issues do not reject the party.
    static List<BadRecord> exceptions(Validated v, EtlContext ctx) {
        var name = v.personName();
        var gender = v.src().genderCd();
        return Stream.of(
                missingNameCode(v.name().first(), v.name().last()) == null ? null
                        : badData4Name(ctx, v.pkey(), name.first(), name.middle(), name.last(), v.birth().value(),
                                v.src().createDt(), Infa.isMissing(name.first()) ? name.first() : name.last()),
                v.gender().exception().configured()
                        ? badData4Gender(ctx, v.pkey(), null, name, v.birth().value(), gender, v.gender().exception())
                        : null,
                v.death().configured() ? badData4DeathDate(ctx, v.pkey(), name, v.birth().value(), gender,
                        v.src().deathDt(), v.src().createDt(), v.death()) : null,
                v.birth().invalid() ? badData4BirthDate(ctx, v.pkey(), null, name, v.src().dobDt(), gender,
                        v.birth().exception()) : null)
                .filter(java.util.Objects::nonNull).toList();
    }
}
