package com.idq.cli.source.eci.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.badData4Name;
import static com.idq.cli.core.EtlPatterns.missingNameCode;
import static com.idq.cli.core.Infa.lpad;

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
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyValidation;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyName;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.eci.etldb.repo.EciChildDeltaRepository;
import com.idq.cli.source.eci.etldb.repo.EciDupCasesViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciFamilyValidationViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveLogRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveStatusRepository;
import com.idq.cli.source.eci.etldb.repo.EciPartyXrefRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_ECI_Pty_Validation` - decides which children and family members are (de)activated.
/// See [docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md].
@Service
public class EciPartyValidationService {

    public static final MappingInfo INFO = MappingInfo.of("013", "m_Tgt_C_S_ECI_Pty_Validation", SourceSystem.ECI,
            List.of(EciSources.InactiveStatus.class, EciSources.InactiveLog.class), List.of(EciSources.ChildDelta.class,
            EciSources.FamilyDelta.class, MdmBaseTables.PartyXref.class, EciSources.InactiveStatus.class,
            EciSources.EtlLuDupCases.class, EciSources.EtlLuFamilyValidation.class));

    /// @param duplicateCases `<source table>|<id>` of parties whose every case is a duplicate (reason 8)
    /// @param familyFlags    `<source table>|<id>` of family members with any family validation status
    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates, Set<String> duplicateCases,
            Set<String> familyFlags) {}

    private final EciChildDeltaRepository childDelta;
    private final EciInactiveStatusRepository inactiveStatuses;
    private final EciInactiveLogRepository inactiveLog;
    private final EciPartyXrefRepository partyXref;
    private final EciDupCasesViewRepository duplicateCases;
    private final EciFamilyValidationViewRepository familyValidations;
    private final BadRecordRepository badRecords;

    public EciPartyValidationService(EciChildDeltaRepository childDelta, EciInactiveStatusRepository inactiveStatuses,
            EciInactiveLogRepository inactiveLog, EciPartyXrefRepository partyXref,
            EciDupCasesViewRepository duplicateCases, EciFamilyValidationViewRepository familyValidations,
            BadRecordRepository badRecords) {
        this.childDelta = childDelta;
        this.inactiveStatuses = inactiveStatuses;
        this.inactiveLog = inactiveLog;
        this.partyXref = partyXref;
        this.duplicateCases = duplicateCases;
        this.familyValidations = familyValidations;
        this.badRecords = badRecords;
    }

    /// Names of every child and family member.
    public List<PartyName> fetchPartyNames() {
        return childDelta.fetchPartyNames();
    }

    /// Current deactivations, MDM hub states, duplicate cases and flagged family members.
    public Lookups fetchValidationLookups() {
        return new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses())),
                LookupRows.toNumberMap(partyXref.fetchHubStates()),
                LookupRows.toMap(duplicateCases.fetchDuplicateCases()).keySet(),
                familyValidations.fetchFamilyValidations().stream().filter(EciPartyValidationService::flagged)
                        .map(f -> f.sourceTable() + "|" + f.idFamily()).collect(Collectors.toSet()));
    }

    static boolean flagged(FamilyValidation f) {
        return f.famNameStatus() != null || f.famPhoneAndAddressSts() != null || f.famInactiveSts() != null;
    }

    /// Party source key: the id left-padded to 10 digits, family members suffixed with `F`.
    public static String partyKey(String sourceTable, Object id) {
        return Infa.concat(lpad(id, 10, '0'), "ECI_FAMILY".equals(sourceTable) ? "F" : "");
    }

    public MappingOutput transform(List<PartyName> rows, Lookups lookups, EtlContext ctx) {
        var changes = new InactiveStatus.Changes("ECI", ctx.runStart());
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var key = partyKey(r.sourceTable(), r.id());
            var name = NameStandardization.standardize(new NameStandardization.Input(r.firstName(),
                    r.middleInitial(), r.lastName(), Infa.fullName(r.firstName(), r.middleInitial(), r.lastName()),
                    null, null, "ECI"), ctx);
            var status = lookups.inactive().status(key);
            boolean nameMissing = missingNameCode(name.first(), name.last()) != null;
            boolean duplicate = lookups.duplicateCases().contains(r.sourceTable() + "|" + r.id());
            boolean familyInactive = lookups.familyFlags().contains(r.sourceTable() + "|" + r.id());
            if (nameMissing && !familyInactive) {
                bad.add(badData4Name(ctx, key, name.first(), name.middle(), name.last(), r.dob(), r.dateCreated(),
                        Infa.isMissing(name.first()) ? name.first() : name.last()));
            }
            if (nameMissing || duplicate || familyInactive) {
                changes.deactivate(key, lookups.hubStates().get(key), status);
            }
            if (status.isPresent() && hasLength(name.first()) && hasLength(name.last()) && !duplicate
                    && !familyInactive) {
                changes.reactivate(key);
            }
        }
        return InactiveStatus.output(changes, bad, EciSources.InactiveStatus.class, EciSources.InactiveStatus::new,
                EciSources.InactiveLog.class, EciSources.InactiveLog::new);
    }

    static boolean hasLength(String value) {
        return value != null && !value.stripTrailing().isEmpty();
    }

    /// Log every change, record the new deactivations, then the
    /// exceptions.
    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(EciInactiveLogRepository.TABLE, logActivationChanges(output.rows(EciSources.InactiveLog.class)));
        for (var batch : output.batches(EciSources.InactiveStatus.class)) {
            loaded.merge(EciInactiveStatusRepository.TABLE, recordNewDeactivations(batch.rows()), Integer::sum);
        }
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int logActivationChanges(List<EciSources.InactiveLog> logs) {
        return inactiveLog.insertAll(logs).size();
    }

    int recordNewDeactivations(List<EciSources.InactiveStatus> deactivated) {
        return inactiveStatuses.insertAll(deactivated).size();
    }
}
