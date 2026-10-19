package com.idq.cli.source.fss;

import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.reference.ReferenceData;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.fss.FssQueries.ClientRelation;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_FSS_Pty_Rle_Rel` - relations between a client and the related registration client.
/// See [docs/mappings/024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md].
@Component
public class FssRelationship extends SourceMapping<ClientRelation, InactiveStatus.Lookup>
        implements MemberMapping.Role<ClientRelation, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("024", "m_Tgt_C_S_FSS_Pty_Rle_Rel", SourceSystem.FSS,
            List.of("C_S_FSS_PTY_RLE_REL"), List.of("V_FSS_ETL_SRC_RELATIONS", "STG_FSS_PTY_INACTIVE_STS"));

    public FssRelationship(FssQueries queries) {
        super(INFO, queries::fetchClientRelations,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    static boolean toChild(ClientRelation r) {
        return "To Child".equals(r.relationDirection());
    }

    /// A missing relation is treated as `CAREGIVER`; the code is combined with the gender of the related party
    /// ("To Child": the family member's, otherwise the child's).
    public static String relationCode(ClientRelation r) {
        var relation = r.cdReltshpToTc() == null ? "CAREGIVER" : r.cdReltshpToTc();
        return pipe(relation, toChild(r) ? r.relnCdGender() : r.cdGender());
    }

    public static String codeType(ClientRelation r) {
        return toChild(r) ? "REL_TP" : "INVERSE_REL";
    }

    public static String fromRole(ClientRelation r) {
        return (toChild(r) ? r.relnPtySrcKey() : r.ptySrcKey()) + "|Member";
    }

    public static String toRole(ClientRelation r) {
        return (toChild(r) ? r.ptySrcKey() : r.relnPtySrcKey()) + "|Member";
    }

    /// `<from role>|<to role>|<MDM relationship code>`
    public static String pkey(ClientRelation r, String relationshipType) {
        return pipe(fromRole(r), toRole(r), relationshipType);
    }

    @Override
    public MappingOutput transform(List<ClientRelation> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var relationships = new ArrayList<FssTargets.Relationship>();
        var bad = new ArrayList<BadRecord>();
        rows.stream().filter(r -> inactive.isActive(r.ptySrcKey()) && inactive.isActive(r.relnPtySrcKey()))
                .forEach(r -> {
                    var code = relationCode(r);
                    var type = ctx.reference().codeValue(codeType(r), "FSS", code)
                            .map(ReferenceData.CodeValue::mstrRefCode).orElse(null);
                    if (type == null) {
                        bad.add(ctx.badRecord().ids(r.relnIdClient(), r.idClient(), r.idRegistration())
                                .exception(ctx.exception("Invalid_Relationship"))
                                .attribute("Relationship|Sex", code).person(null, r.cdGender(), null)
                                .period(r.relnDtCreated(), null).build());
                        return;
                    }
                    var key = pkey(r, type);
                    var audit = MdmAudit.srcRowid(key).periodStart(r.relnDtCreated()).lastUpdated(ctx.runStart())
                            .created(r.relnDtLastUpdate()).by("batchload", "batchload").hubState(1)
                            .sourceUpdated(r.relnDtLastUpdate());
                    relationships.add(new FssTargets.Relationship(key, audit, new Columns.Relationship(fromRole(r),
                            toRole(r), "Member Relationship", "Member", type)));
                });
        return MappingOutput.empty().load(TargetBatch.replaceAll(FssTargets.Relationship.class,
                Rows.lastPerKey(relationships, FssTargets.Relationship::pkeySrcObject))).reject(bad);
    }
}
