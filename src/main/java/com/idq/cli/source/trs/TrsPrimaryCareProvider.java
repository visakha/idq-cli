package com.idq.cli.source.trs;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.PrimaryCareProvider;
import com.idq.cli.source.trs.TrsQueries.ProviderKey;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP` - member to primary care provider (or clinic) relationships.
/// See [docs/mappings/010_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md].
@Component
public class TrsPrimaryCareProvider extends SourceMapping<PrimaryCareProvider, TrsPrimaryCareProvider.Lookups>
        implements MemberMapping.Role<PrimaryCareProvider, TrsPrimaryCareProvider.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("010", "m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP",
            SourceSystem.TRS, List.of("C_S_TRS_PTY_RLE_REL_PROV"), List.of(TrsSources.InManagedCareDelta.class,
            TrsTargets.ValidMember.class, MdmBaseTables.PartyRoleAltId.class, MdmBaseTables.PartyRoleAltIdXref.class));

    /// IDQ parameter `$PCP_REL_TP`.
    public static final String PCP_REL_TP = "100";

    /// @param providerKeyByTpi provider TPI to its MDM party-role source key
    public record Lookups(Map<String, String> providerKeyByTpi) {}

    public TrsPrimaryCareProvider(TrsQueries queries) {
        super(INFO, queries::fetchPrimaryCareProviders, () -> new Lookups(queries.fetchProviderKeys().stream()
                .collect(Collectors.toMap(ProviderKey::altIdVal, ProviderKey::pkeySrcObject, (a, b) -> a))));
    }

    /// The provider party-role key is the provider source key up to (not including) its second `|`.
    public static String providerRoleKey(String providerSourceKey) {
        var key = trim(providerSourceKey);
        if (key == null) {
            return null;
        }
        int first = key.indexOf('|');
        int second = first < 0 ? -1 : key.indexOf('|', first + 1);
        return second < 0 ? "" : key.substring(0, second);
    }

    /// `<member key>|Member|<provider role key>|100`
    public static String pkey(String memberPartyKey, String providerRoleKey) {
        return pipe(memberPartyKey == null ? null : memberRole(trim(memberPartyKey)), providerRoleKey, PCP_REL_TP);
    }

    @Override
    public MappingOutput transform(List<PrimaryCareProvider> rows, Lookups lookups, EtlContext ctx) {
        var relationships = new ArrayList<TrsTargets.ProviderRelationship>();
        var bad = new ArrayList<BadRecord>();
        rows.stream().filter(r -> Infa.isNumber(r.providerNum())).forEach(r -> {
            var providerKey = lookups.providerKeyByTpi().get(r.providerNum());
            var fk1 = r.ptyPk() == null ? null : memberRole(trim(r.ptyPk()));
            var fk2 = providerRoleKey(providerKey);
            var relTypeCode = providerKey != null && trim(providerKey).contains("|HCO") ? "Member PCO" : "Member PCP";
            var key = pkey(r.ptyPk(), fk2);
            boolean backwards = r.beginDt() != null && r.endDt() != null && r.beginDt().isAfter(r.endDt());
            if (backwards) {
                bad.add(ctx.badRecord().ids(r.indvId(), r.providerNum(), fk2)
                        .exception(ctx.exception("Period_Start_Date_>_Period_End_Date"))
                        .attribute("Effective Date", null).period(r.beginDt(), r.endDt()).build());
            } else if (fk1 != null && fk2 != null) {
                var audit = MdmAudit.srcRowid(key).period(r.beginDt(), r.endDt()).lastUpdated(ctx.runStart())
                        .sourceUpdated(r.createDt());
                relationships.add(new TrsTargets.ProviderRelationship(key, audit,
                        new Columns.Relationship(fk1, fk2, relTypeCode, "Member", PCP_REL_TP)));
            } else {
                var code = fk1 == null ? "Invalid_Member" : "Invalid_PCP";
                bad.add(ctx.badRecord().ids(r.indvId(), r.providerNum(), null).exception(ctx.exception(code))
                        .attribute("Provider", r.providerNum()).period(r.beginDt(), r.endDt()).build());
            }
        });
        return MappingOutput.empty().load(TargetBatch.replaceAll(TrsTargets.ProviderRelationship.class,
                Rows.currentSegmentPerKey(relationships))).reject(bad);
    }
}
