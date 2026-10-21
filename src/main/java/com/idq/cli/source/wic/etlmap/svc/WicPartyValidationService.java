package com.idq.cli.source.wic.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.badData4Name;
import static com.idq.cli.core.EtlPatterns.missingNameCode;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.core.target.LoadMode;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientName;
import com.idq.cli.source.wic.etldb.models.WicSources;
import com.idq.cli.source.wic.etldb.repo.WicEtlSrcViewRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveLogRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveStatusRepository;
import com.idq.cli.source.wic.etldb.repo.WicPartyXrefRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_WIC_Pty_Validation` - decides which WIC clients are (de)activated.
/// See [docs/mappings/029_m_Tgt_C_S_WIC_Pty_Validation.md].
@Service
public class WicPartyValidationService {

    public static final MappingInfo INFO = MappingInfo.of("029", "m_Tgt_C_S_WIC_Pty_Validation", SourceSystem.WIC,
            List.of(WicSources.InactiveStatus.class, WicSources.InactiveLog.class), List.of(WicSources.EtlSrc.class,
            MdmBaseTables.PartyXref.class, WicSources.InactiveStatus.class));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates) {}

    private final WicEtlSrcViewRepository etlSrc;
    private final WicInactiveStatusRepository inactiveStatuses;
    private final WicPartyXrefRepository partyXref;
    private final WicInactiveLogRepository inactiveLog;
    private final BadRecordRepository badRecords;

    public WicPartyValidationService(WicEtlSrcViewRepository etlSrc, WicInactiveStatusRepository inactiveStatuses,
            WicPartyXrefRepository partyXref, WicInactiveLogRepository inactiveLog, BadRecordRepository badRecords) {
        this.etlSrc = etlSrc;
        this.inactiveStatuses = inactiveStatuses;
        this.partyXref = partyXref;
        this.inactiveLog = inactiveLog;
        this.badRecords = badRecords;
    }

    /// The `IdqMapInitQuery`.
    public List<ClientName> fetchClientNames() {
        return etlSrc.fetchClientNames();
    }

    /// Current deactivations and the MDM hub state of each party.
    public Lookups fetchValidationLookups() {
        return new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses())),
                LookupRows.toNumberMap(partyXref.fetchHubStates()));
    }

    /// A missing first or last name deactivates the client; a deactivated client with both names is reactivated.
    public MappingOutput transform(List<ClientName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("WIC", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = r.ptySrcKey();
            var name = NameStandardization.standardize(new NameStandardization.Input(r.firstName(), r.middleName(),
                    r.lastName(), Infa.fullName(r.firstName(), r.middleName(), r.lastName()), null, null, "WIC"), ctx);
            var status = lookups.inactive().status(key);
            if (missingNameCode(name.first(), name.last()) != null) {
                bad.add(badData4Name(ctx, key, name.first(), name.middle(), name.last(), r.dob(), r.datekey(),
                        Infa.isMissing(name.first()) ? name.first() : name.last()));
                changes.deactivate(key, lookups.hubStates().get(key), status);
            } else if (status.isPresent()) {
                changes.reactivate(key);
            }
        }
        return InactiveStatus.output(changes, bad, WicSources.InactiveStatus.class, WicSources.InactiveStatus::new,
                WicSources.InactiveLog.class, WicSources.InactiveLog::new);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(WicInactiveLogRepository.TABLE, logActivationChanges(output.rows(WicSources.InactiveLog.class)));
        for (var batch : output.batches(WicSources.InactiveStatus.class)) {
            loaded.merge(WicInactiveStatusRepository.TABLE, batch.mode() instanceof LoadMode.DeleteByKey<?>
                    ? removeReactivatedStatuses(batch.rows()) : recordNewDeactivations(batch.rows()), Integer::sum);
        }
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int logActivationChanges(List<WicSources.InactiveLog> logs) {
        return inactiveLog.insertAll(logs).size();
    }

    int removeReactivatedStatuses(List<WicSources.InactiveStatus> reactivated) {
        return reactivated.stream()
                .mapToInt(s -> inactiveStatuses.deleteBySrcKeyAndRowidSystem(s.srcKey(), s.rowidSystem())).sum();
    }

    int recordNewDeactivations(List<WicSources.InactiveStatus> deactivated) {
        return inactiveStatuses.insertAll(deactivated).size();
    }
}
