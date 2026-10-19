package com.idq.cli.source.eci;

import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
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
import com.idq.cli.source.eci.EciQueries.FamilyRelation;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_ECI_Pty_Rle_Rel` - child / family member relationships in both directions.
/// See [docs/mappings/018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md].
@Component
public class EciRelationship extends SourceMapping<FamilyRelation, EciRelationship.Lookups>
        implements MemberMapping.Role<FamilyRelation, EciRelationship.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("018", "m_Tgt_C_S_ECI_Pty_Rle_Rel", SourceSystem.ECI,
            List.of("C_S_ECI_PTY_RLE_REL"), List.of(EciSources.DFamily.class, EciSources.SnChild.class,
            EciTargets.InactiveStatus.class));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, String> childGender) {}

    public EciRelationship(EciQueries queries) {
        super(INFO, queries::fetchFamilyRelations, () -> new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())),
                LookupRows.toMap(queries.fetchChildGenders())));
    }

    public static String childKey(Long idChild) {
        return lpad(idChild, 10, '0');
    }

    public static String familyKey(Long idFamily) {
        return Infa.concat(lpad(idFamily, 10, '0'), "F");
    }

    /// "To Child" relates the family member to the child, "From Child" the child to the family member.
    public static String fromRole(FamilyRelation r) {
        return ("To Child".equals(r.relationDirection()) ? familyKey(r.idFamily()) : childKey(r.idChild()))
                + "|Member";
    }

    public static String toRole(FamilyRelation r) {
        return ("To Child".equals(r.relationDirection()) ? childKey(r.idChild()) : familyKey(r.idFamily()))
                + "|Member";
    }

    /// `<from role>|<to role>|<MDM relationship code>`
    public static String pkey(FamilyRelation r, String relationshipType) {
        return pipe(fromRole(r), toRole(r), relationshipType);
    }

    /// The family code alone for "To Child"; for "From Child" combined with the child's gender.
    public static String relationCode(FamilyRelation r, String childGender) {
        return "To Child".equals(r.relationDirection()) ? r.familyCd() : pipe(r.familyCd(), childGender);
    }

    /// `Lkp_Rel_Tp_Code_Value`: `CODE_TYPE IN ('REL_TP', 'INVERSE_REL')`, any matching row.
    static Optional<ReferenceData.CodeValue> relationType(String code, EtlContext ctx) {
        return ctx.reference().codeValue("REL_TP", "ECI", code)
                .or(() -> ctx.reference().codeValue("INVERSE_REL", "ECI", code));
    }

    @Override
    public MappingOutput transform(List<FamilyRelation> rows, Lookups lookups, EtlContext ctx) {
        var relationships = new ArrayList<EciTargets.Relationship>();
        var bad = new ArrayList<BadRecord>();
        rows.stream()
                .filter(r -> lookups.inactive().isActive(childKey(r.idChild()))
                        && lookups.inactive().isActive(familyKey(r.idFamily())))
                .forEach(r -> {
                    var code = relationCode(r, lookups.childGender().get(Infa.toChar(r.idChild())));
                    var type = relationType(code, ctx).map(ReferenceData.CodeValue::mstrRefCode).orElse(null);
                    var key = pkey(r, type);
                    if (type == null) {
                        bad.add(ctx.badRecord().ids(r.idFamily(), r.idChild(), key)
                                .exception(ctx.exception("Invalid_Relationship")).attribute("FAMILY_CD", code)
                                .period(r.dateCreated(), null).build());
                        return;
                    }
                    var audit = MdmAudit.srcRowid(key).periodStart(r.dateCreated()).lastUpdated(ctx.runStart())
                            .created(r.dateModified()).by(ctx.mappingName(), ctx.mappingName()).hubState(1)
                            .sourceUpdated(r.dateModified());
                    relationships.add(new EciTargets.Relationship(key, audit, new Columns.Relationship(fromRole(r),
                            toRole(r), "Member Relationship", "Member", type)));
                });
        return MappingOutput.empty().load(TargetBatch.replaceAll(EciTargets.Relationship.class,
                Rows.lastPerKey(relationships, EciTargets.Relationship::pkeySrcObject))).reject(bad);
    }
}
