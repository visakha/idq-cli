package com.idq.cli.source.ttf.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
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
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientIdentifier;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import com.idq.cli.source.ttf.etldb.models.TtfTargets;
import com.idq.cli.source.ttf.etldb.repo.TtfAlternateIdRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfEtlSrcViewRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfInactiveStatusRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` - the TTF party source key as alternate id `024`.
/// See [docs/mappings/027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md].
@Service
public class TtfAlternateIdService {

    public static final MappingInfo INFO = MappingInfo.of("027", "m_Tgt_C_S_TTF_Pty_Rle_Alt_Id", SourceSystem.TTF,
            List.of("C_S_TTF_PTY_RLE_ALT_ID"), List.of(TtfSources.EtlSrc.class, TtfTargets.InactiveStatus.class));

    public static final String ALT_ID_TYPE = "024";

    private final TtfEtlSrcViewRepository etlSrc;
    private final TtfInactiveStatusRepository inactiveStatuses;
    private final TtfAlternateIdRepository alternateIds;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TtfAlternateIdService(TtfEtlSrcViewRepository etlSrc, TtfInactiveStatusRepository inactiveStatuses,
            TtfAlternateIdRepository alternateIds, BadRecordRepository badRecords, EtlSettings settings) {
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

    /// `<party key>|Member|024|<party key>`
    public static String pkey(String partyKey) {
        return pipe(memberRole(partyKey), ALT_ID_TYPE, partyKey);
    }

    public MappingOutput transform(List<ClientIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = Rows.where(rows, r -> inactive.isActive(r.ptySrcKey())).stream().map(r -> {
            var key = pkey(r.ptySrcKey());
            var audit = MdmAudit.srcRowid(key).periodStart(ctx.runStart()).lastUpdated(ctx.runStart())
                    .created(r.submitdate()).hubState(1).sourceUpdated(r.submitdate());
            return new TtfTargets.AlternateId(key, audit, new Columns.AlternateId(memberRole(r.ptySrcKey()),
                    ALT_ID_TYPE, r.ptySrcKey(), "Issued", ALT_ID_TYPE, null));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(TtfTargets.AlternateId.class,
                Rows.lastPerKey(ids, TtfTargets.AlternateId::pkeySrcObject)));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TtfAlternateIdRepository.TABLE, replaceAlternateIds(output.rows(TtfTargets.AlternateId.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceAlternateIds(List<TtfTargets.AlternateId> rows) {
        settings.requireClearable(TtfAlternateIdRepository.TABLE);
        alternateIds.deleteAll();
        return alternateIds.insertAll(rows).size();
    }
}
