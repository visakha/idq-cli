package com.idq.cli.source.fss.etlmap.svc;

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
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientName;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveLogRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import com.idq.cli.source.fss.etldb.repo.FssPartyXrefRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_FSS_Pty_Validation` - decides which FSS clients are (de)activated.
/// See [docs/mappings/019_m_Tgt_C_S_FSS_Pty_Validation.md].
@Service
public class FssPartyValidationService {

    public static final MappingInfo INFO = MappingInfo.of("019", "m_Tgt_C_S_FSS_Pty_Validation", SourceSystem.FSS,
            List.of("STG_FSS_PTY_INACTIVE_STS", "STG_FSS_PTY_INACTIVE_LOG"), List.of(FssSources.EtlSrc.class,
            MdmBaseTables.PartyXref.class, FssSources.InactiveStatus.class));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates) {}

    private final FssEtlSrcViewRepository etlSrc;
    private final FssInactiveStatusRepository inactiveStatuses;
    private final FssPartyXrefRepository partyXref;
    private final FssInactiveLogRepository inactiveLog;
    private final BadRecordRepository badRecords;

    public FssPartyValidationService(FssEtlSrcViewRepository etlSrc, FssInactiveStatusRepository inactiveStatuses,
            FssPartyXrefRepository partyXref, FssInactiveLogRepository inactiveLog, BadRecordRepository badRecords) {
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

    /// Deactivate on a missing name, a deleted client (`CLIENT_DTL__CAPXACTION = 'D'`) or when every registration
    /// is inactive. Reactivate a deactivated client that is complete again.
    ///
    /// As in IDQ, the reactivation is written into `STG_FSS_PTY_INACTIVE_STS` with status `Reactivation` (not into
    /// the log) after the old status row is deleted - see the mapping document.
    public MappingOutput transform(List<ClientName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("FSS", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = r.ptySrcKey();
            var name = NameStandardization.standardize(new NameStandardization.Input(r.nmFirst(), r.nmMiddle(),
                    r.nmLast(), Infa.fullName(r.nmFirst(), r.nmMiddle(), r.nmLast()), null, null, "FSS"), ctx);
            var status = lookups.inactive().status(key);
            boolean nameMissing = missingNameCode(name.first(), name.last()) != null;
            if (nameMissing) {
                bad.add(badData4Name(ctx, key, name.first(), name.middle(), name.last(), r.dtDob(), r.dtLastUpdate(),
                        name.srcFull()));
            }
            if (nameMissing || "D".equals(r.clientDtlCapxaction()) || "Y".equals(r.lastInactvClientYn())) {
                changes.deactivate(key, lookups.hubStates().get(key), status);
            }
            if (status.isPresent() && hasLength(name.first()) && hasLength(name.last())
                    && r.clientDtlCapxaction() != null && !"D".equals(r.clientDtlCapxaction())
                    && r.lastInactvClientYn() != null && !"Y".equals(r.lastInactvClientYn())) {
                changes.reactivate(key);
            }
        }
        var reactivations = changes.logs.stream().filter(l -> l.action().equals("Reactivation"))
                .map(l -> new FssSources.InactiveStatus(l.srcKey(), l.rowidSystem(), l.action(), l.actionDt()))
                .toList();
        changes.logs.removeIf(l -> l.action().equals("Reactivation"));
        return InactiveStatus.output(changes, bad, FssSources.InactiveStatus.class, FssSources.InactiveStatus::new,
                FssSources.InactiveLog.class, FssSources.InactiveLog::new)
                .load(TargetBatch.append(FssSources.InactiveStatus.class, reactivations));
    }

    static boolean hasLength(String value) {
        return value != null && !value.stripTrailing().isEmpty();
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(FssInactiveLogRepository.TABLE, logActivationChanges(output.rows(FssSources.InactiveLog.class)));
        for (var batch : output.batches(FssSources.InactiveStatus.class)) {
            loaded.merge(FssInactiveStatusRepository.TABLE, batch.mode() instanceof LoadMode.DeleteByKey<?>
                    ? removeReactivatedStatuses(batch.rows()) : recordNewDeactivations(batch.rows()), Integer::sum);
        }
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int logActivationChanges(List<FssSources.InactiveLog> logs) {
        return inactiveLog.insertAll(logs).size();
    }

    int removeReactivatedStatuses(List<FssSources.InactiveStatus> reactivated) {
        return reactivated.stream()
                .mapToInt(s -> inactiveStatuses.deleteBySrcKeyAndRowidSystem(s.srcKey(), s.rowidSystem())).sum();
    }

    int recordNewDeactivations(List<FssSources.InactiveStatus> deactivated) {
        return inactiveStatuses.insertAll(deactivated).size();
    }
}
