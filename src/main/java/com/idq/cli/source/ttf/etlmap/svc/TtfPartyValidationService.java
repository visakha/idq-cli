package com.idq.cli.source.ttf.etlmap.svc;

import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.isMissing;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.trim;
import static com.idq.cli.core.Infa.upper;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientName;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import com.idq.cli.source.ttf.etldb.repo.TtfEtlSrcViewRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfInactiveLogRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfInactiveStatusRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfPartyXrefRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TTF_Pty_Validation` - decides which TTF clients are (de)activated.
/// See [docs/mappings/025_m_Tgt_C_S_TTF_Pty_Validation.md].
@Service
public class TtfPartyValidationService {

    public static final MappingInfo INFO = MappingInfo.of("025", "m_Tgt_C_S_TTF_Pty_Validation", SourceSystem.TTF,
            List.of(TtfSources.InactiveStatus.class, TtfSources.InactiveLog.class), List.of(TtfSources.EtlSrc.class,
            MdmBaseTables.PartyXref.class, TtfSources.InactiveStatus.class));

    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates) {}

    private final TtfEtlSrcViewRepository etlSrc;
    private final TtfInactiveStatusRepository inactiveStatuses;
    private final TtfPartyXrefRepository partyXref;
    private final TtfInactiveLogRepository inactiveLog;
    private final BadRecordRepository badRecords;

    public TtfPartyValidationService(TtfEtlSrcViewRepository etlSrc, TtfInactiveStatusRepository inactiveStatuses,
            TtfPartyXrefRepository partyXref, TtfInactiveLogRepository inactiveLog, BadRecordRepository badRecords) {
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

    public static String partyKey(Long clientsId) {
        return lpad(clientsId, 10, '0');
    }

    static boolean declined(String name) {
        return in(upper(name), "DECLINED");
    }

    static boolean withheld(String name) {
        return in(upper(name), "DECLINED", "DO_NOT_DISCLOSE");
    }

    /// `Missing_First_Name`, `Invalid_First_Name` (declined / not disclosed), then the same for the last name.
    public static String nameExceptionCode(String first, String last) {
        if (isMissing(first)) {
            return "Missing_First_Name";
        }
        if (in(upper(trim(first)), "DECLINED", "DO_NOT_DISCLOSE")) {
            return "Invalid_First_Name";
        }
        if (isMissing(last)) {
            return "Missing_Last_Name";
        }
        return in(upper(trim(last)), "DECLINED", "DO_NOT_DISCLOSE") ? "Invalid_Last_Name" : "Valid";
    }

    public MappingOutput transform(List<ClientName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("TTF", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = partyKey(r.clientsId());
            var name = NameStandardization.standardize(new NameStandardization.Input(r.firstname(), r.middlename(),
                    r.lastname(), Infa.fullName(r.firstname(), r.middlename(), r.lastname()), null, null, "TTF"),
                    ctx);
            var first = name.first();
            var last = name.last();
            var status = lookups.inactive().status(key);
            boolean missing = isMissing(first) || isMissing(last);
            if (missing || withheld(first) || withheld(last)) {
                var code = nameExceptionCode(first, last);
                bad.add(ctx.badRecord().ids(key, null, null).exception(ctx.exception(code))
                        .attribute(code, name.srcFull()).name(null, first, name.middle(), last, null)
                        .person(r.dob(), null, null).build());
            }
            if (missing || declined(first) || declined(last) || "N".equals(r.clientExistsFlag())) {
                changes.deactivate(key, lookups.hubStates().get(key), status);
            }
            if (status.isPresent() && !missing && !declined(first) && !declined(last)
                    && "Y".equals(r.clientExistsFlag())) {
                changes.reactivate(key);
            }
        }
        return InactiveStatus.output(changes, bad, TtfSources.InactiveStatus.class, TtfSources.InactiveStatus::new,
                TtfSources.InactiveLog.class, TtfSources.InactiveLog::new);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TtfInactiveLogRepository.TABLE, logActivationChanges(output.rows(TtfSources.InactiveLog.class)));
        for (var batch : output.batches(TtfSources.InactiveStatus.class)) {
            loaded.merge(TtfInactiveStatusRepository.TABLE, recordNewDeactivations(batch.rows()), Integer::sum);
        }
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int logActivationChanges(List<TtfSources.InactiveLog> logs) {
        return inactiveLog.insertAll(logs).size();
    }

    int recordNewDeactivations(List<TtfSources.InactiveStatus> deactivated) {
        return inactiveStatuses.insertAll(deactivated).size();
    }
}
