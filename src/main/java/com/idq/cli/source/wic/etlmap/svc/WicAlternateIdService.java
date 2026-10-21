package com.idq.cli.source.wic.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientIdentifier;
import com.idq.cli.source.wic.etldb.models.WicSources;
import com.idq.cli.source.wic.etldb.models.WicTargets;
import com.idq.cli.source.wic.etldb.repo.WicAlternateIdRepository;
import com.idq.cli.source.wic.etldb.repo.WicEtlSrcViewRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveStatusRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` - WIC client id (`020`) or family id (`021`).
/// See [docs/mappings/032_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md].
@Service
public class WicAlternateIdService {

    public static final MappingInfo INFO = MappingInfo.of("032", "m_Tgt_C_S_WIC_Pty_Rle_Alt_Id", SourceSystem.WIC,
            List.of("C_S_WIC_PTY_RLE_ALT_ID"), List.of(WicSources.EtlSrc.class, WicTargets.InactiveStatus.class));

    private final WicEtlSrcViewRepository etlSrc;
    private final WicInactiveStatusRepository inactiveStatuses;
    private final WicAlternateIdRepository alternateIds;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public WicAlternateIdService(WicEtlSrcViewRepository etlSrc, WicInactiveStatusRepository inactiveStatuses,
            WicAlternateIdRepository alternateIds, BadRecordRepository badRecords, EtlSettings settings) {
        this.etlSrc = etlSrc;
        this.inactiveStatuses = inactiveStatuses;
        this.alternateIds = alternateIds;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<ClientIdentifier> fetchClientIdentifiers() {
        return etlSrc.fetchClientIdentifiers();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    public static String altIdType(String sourceTable) {
        return "CLIENT".equals(sourceTable) ? "020" : "021";
    }

    /// `<party key>|Member|<020 or 021>|<id, 12 digits>`
    public static String pkey(ClientIdentifier r) {
        return pipe(memberRole(r.ptySrcKey()), altIdType(r.sourceTable()), lpad(r.id(), 12, '0'));
    }

    public MappingOutput transform(List<ClientIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = Rows.where(rows, r -> inactive.isActive(r.ptySrcKey())).stream().map(r -> {
            var type = altIdType(r.sourceTable());
            var audit = MdmAudit.srcRowid(pipe(r.id(), type)).periodStart(r.datekey()).lastUpdated(ctx.runStart())
                    .created(r.datekey()).sourceUpdated(r.datekey());
            return new WicTargets.AlternateId(pkey(r), audit, new Columns.AlternateId(memberRole(r.ptySrcKey()), type,
                    lpad(r.id(), 12, '0'), "Issued", type, null));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(WicTargets.AlternateId.class,
                Rows.lastPerKey(ids, WicTargets.AlternateId::pkeySrcObject)));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(WicAlternateIdRepository.TABLE, replaceAlternateIds(output.rows(WicTargets.AlternateId.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceAlternateIds(List<WicTargets.AlternateId> rows) {
        settings.requireClearable(WicAlternateIdRepository.TABLE);
        alternateIds.deleteAll();
        return alternateIds.insertAll(rows).size();
    }
}
