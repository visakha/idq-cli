package com.idq.cli.source.fss.etlmap.svc;

import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.reference.ReferenceData;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.FssTargets;
import com.idq.cli.mdmdc.etldb.repo.FssRelationshipRepository;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientRelation;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcRelationsViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_FSS_Pty_Rle_Rel` - relations between a client and the related registration client.
/// See [docs/mappings/024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md].
@Service
public class FssRelationshipService {

    public static final MappingInfo INFO = MappingInfo.of("024", "m_Tgt_C_S_FSS_Pty_Rle_Rel", SourceSystem.FSS,
            List.of(FssTargets.Relationship.class), List.of(FssSources.EtlSrcRelations.class,
            FssSources.InactiveStatus.class));

    private final FssEtlSrcRelationsViewRepository etlSrcRelations;
    private final FssInactiveStatusRepository inactiveStatuses;
    private final FssRelationshipRepository relationships;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public FssRelationshipService(FssEtlSrcRelationsViewRepository etlSrcRelations,
            FssInactiveStatusRepository inactiveStatuses, FssRelationshipRepository relationships,
            BadRecordRepository badRecords, EtlSettings settings) {
        this.etlSrcRelations = etlSrcRelations;
        this.inactiveStatuses = inactiveStatuses;
        this.relationships = relationships;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<ClientRelation> fetchClientRelations() {
        return etlSrcRelations.fetchClientRelations();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
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

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(FssRelationshipRepository.TABLE, replaceRelationships(output.rows(FssTargets.Relationship.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceRelationships(List<FssTargets.Relationship> rows) {
        settings.requireClearable(FssRelationshipRepository.TABLE);
        relationships.deleteAll();
        return relationships.insertAll(rows).size();
    }
}
