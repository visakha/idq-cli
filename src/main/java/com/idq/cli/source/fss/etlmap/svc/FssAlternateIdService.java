package com.idq.cli.source.fss.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.FssTargets;
import com.idq.cli.mdmdc.etldb.repo.FssAlternateIdRepository;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientIdentifier;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` - FSS client id (`022`) or registration id (`023`).
/// See [docs/mappings/022_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md].
@Service
public class FssAlternateIdService {

    public static final MappingInfo INFO = MappingInfo.of("022", "m_Tgt_C_S_FSS_Pty_Rle_Alt_Id", SourceSystem.FSS,
            List.of("C_S_FSS_PTY_RLE_ALT_ID"), List.of(FssSources.EtlSrc.class, FssSources.InactiveStatus.class));

    private final FssEtlSrcViewRepository etlSrc;
    private final FssInactiveStatusRepository inactiveStatuses;
    private final FssAlternateIdRepository alternateIds;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public FssAlternateIdService(FssEtlSrcViewRepository etlSrc, FssInactiveStatusRepository inactiveStatuses,
            FssAlternateIdRepository alternateIds, BadRecordRepository badRecords, EtlSettings settings) {
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

    public static String altIdType(String sourceType) {
        return "CLIENT".equals(sourceType) ? "022" : "023";
    }

    /// `<party key>|Member|<022 or 023>|<client id, 10 digits>`
    public static String pkey(ClientIdentifier r) {
        return pipe(memberRole(r.ptySrcKey()), altIdType(r.sourceType()), lpad(r.idClient(), 10, '0'));
    }

    public MappingOutput transform(List<ClientIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = Rows.where(rows, r -> inactive.isActive(r.ptySrcKey())).stream().map(r -> {
            var type = altIdType(r.sourceType());
            var audit = MdmAudit.srcRowid(pipe(Infa.toChar(r.idClient()), type)).periodStart(r.dtCreated())
                    .lastUpdated(ctx.runStart()).created(r.dtCreated()).hubState(1).sourceUpdated(ctx.runStart());
            return new FssTargets.AlternateId(pkey(r), audit, new Columns.AlternateId(memberRole(r.ptySrcKey()), type,
                    lpad(r.idClient(), 10, '0'), "Issued", type, null));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(FssTargets.AlternateId.class,
                Rows.lastPerKey(ids, FssTargets.AlternateId::pkeySrcObject)));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(FssAlternateIdRepository.TABLE, replaceAlternateIds(output.rows(FssTargets.AlternateId.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceAlternateIds(List<FssTargets.AlternateId> rows) {
        settings.requireClearable(FssAlternateIdRepository.TABLE);
        alternateIds.deleteAll();
        return alternateIds.insertAll(rows).size();
    }
}
