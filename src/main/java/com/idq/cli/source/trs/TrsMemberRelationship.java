package com.idq.cli.source.trs;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.MemberRelationship;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` - relationships between two members.
/// See [docs/mappings/009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md].
@Component
public class TrsMemberRelationship extends SourceMapping<MemberRelationship, NoLookups>
        implements MemberMapping.Role<MemberRelationship, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("009", "m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem",
            SourceSystem.TRS, List.of("C_S_TRS_PTY_RLE_REL"), List.of(TrsSources.DDcRelationships.class,
            TrsTargets.ValidMember.class));

    public TrsMemberRelationship(TrsQueries queries) {
        super(INFO, queries::fetchMemberRelationships, NoLookups::none);
    }

    /// `<member key>|Member|<related member key>|Member|<MDM relationship code>`
    public static String pkey(String partyKey, String refPartyKey, String relationshipMasterCode) {
        return pipe(roleOf(partyKey), roleOf(refPartyKey), relationshipMasterCode);
    }

    static String roleOf(String partyKey) {
        return partyKey == null ? null : memberRole(trim(partyKey));
    }

    /// The later of create and update date, or whichever is present.
    public static LocalDateTime sourceLastUpdate(LocalDateTime created, LocalDateTime updated) {
        return Infa.greatest(created, updated);
    }

    @Override
    public MappingOutput transform(List<MemberRelationship> rows, NoLookups lookups, EtlContext ctx) {
        var relationships = new ArrayList<TrsTargets.Relationship>();
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var relType = ctx.reference().masterCode("PTY_REL", "TRS", r.relationshipTypeCd()).orElse(null);
            var fk1 = roleOf(r.ptyPkey());
            var fk2 = roleOf(r.refPtyPkey());
            boolean backwards = r.effBeginDt() != null && r.effEndDt() != null && r.effBeginDt().isAfter(r.effEndDt());
            var exception = ctx.badRecord().ids(r.indvId(), r.refIndvId(), relType)
                    .period(r.effBeginDt(), r.effEndDt());
            if (fk1 == null) {
                bad.add(exception.exception(ctx.exception("Invalid_Member")).build());
            }
            if (fk2 == null) {
                bad.add(exception.exception(ctx.exception("Invalid_Ref_Member")).build());
            }
            if (relType == null) {
                bad.add(ctx.badRecord().ids(r.indvId(), r.refIndvId(), r.relationshipTypeCd())
                        .exception(ctx.exception("Invalid_Rel_Type"))
                        .attribute("Relationship Type", r.relationshipTypeCd())
                        .period(r.effBeginDt(), r.effEndDt()).build());
            }
            if (backwards) {
                bad.add(ctx.badRecord().ids(r.indvId(), r.refIndvId(), r.relationshipTypeCd())
                        .exception(ctx.exception("Period_Start_Date_>_Period_End_Date"))
                        .attribute("Effective Date", null).period(r.effBeginDt(), r.effEndDt()).build());
            }
            if (fk1 != null && fk2 != null && relType != null && !backwards) {
                var key = pkey(r.ptyPkey(), r.refPtyPkey(), relType);
                var audit = MdmAudit.srcRowid(key).period(r.effBeginDt(), r.effEndDt()).lastUpdated(ctx.runStart())
                        .created(r.createDt()).sourceUpdated(sourceLastUpdate(r.createDt(), r.updateDt()));
                relationships.add(new TrsTargets.Relationship(key, audit,
                        new Columns.Relationship(fk1, fk2, "Member Relationship", "Member", relType)));
            }
        }
        return MappingOutput.empty().load(TargetBatch.replaceAll(TrsTargets.Relationship.class,
                Rows.currentSegmentPerKey(relationships))).reject(bad);
    }
}
