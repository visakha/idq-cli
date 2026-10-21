package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberRelationship;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.models.TrsTargets;
import com.idq.cli.source.trs.etldb.repo.TrsDcRelationshipsDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsRelationshipRepository;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` - relationships between two members.
/// See [docs/mappings/009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md].
@Service
public class TrsMemberRelationshipService {

    public static final MappingInfo INFO = MappingInfo.of("009", "m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem",
            SourceSystem.TRS, List.of("C_S_TRS_PTY_RLE_REL"), List.of(TrsSources.DcRelationshipsDelta.class,
            TrsTargets.ValidMember.class));

    private final TrsDcRelationshipsDeltaRepository dcRelationshipsDelta;
    private final TrsRelationshipRepository relationships;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsMemberRelationshipService(TrsDcRelationshipsDeltaRepository dcRelationshipsDelta,
            TrsRelationshipRepository relationships, BadRecordRepository badRecords, EtlSettings settings) {
        this.dcRelationshipsDelta = dcRelationshipsDelta;
        this.relationships = relationships;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<MemberRelationship> fetchMemberRelationships() {
        return dcRelationshipsDelta.fetchMemberRelationships();
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

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsRelationshipRepository.TABLE, replaceRelationships(output.rows(TrsTargets.Relationship.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceRelationships(List<TrsTargets.Relationship> rows) {
        settings.requireClearable(TrsRelationshipRepository.TABLE);
        relationships.deleteAll();
        return relationships.insertAll(rows).size();
    }
}
