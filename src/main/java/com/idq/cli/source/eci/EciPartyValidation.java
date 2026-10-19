package com.idq.cli.source.eci;

import static com.idq.cli.core.EtlPatterns.badData4Name;
import static com.idq.cli.core.EtlPatterns.missingNameCode;
import static com.idq.cli.core.Infa.lpad;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.eci.EciQueries.FamilyValidation;
import com.idq.cli.source.eci.EciQueries.PartyName;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_ECI_Pty_Validation` - decides which children and family members are (de)activated.
/// See [docs/mappings/013_m_Tgt_C_S_ECI_Pty_Validation.md].
@Component
public class EciPartyValidation extends SourceMapping<PartyName, EciPartyValidation.Lookups>
        implements MemberMapping.Demographics<PartyName, EciPartyValidation.Lookups> {

    public static final MappingInfo INFO = MappingInfo.of("013", "m_Tgt_C_S_ECI_Pty_Validation", SourceSystem.ECI,
            List.of("STG_ECI_PTY_INACTIVE_STS", "STG_ECI_PTY_INACTIVE_LOG"),
            List.of("STG_ECI_D_CHILD", "STG_ECI_D_FAMILY", "C_B_PTY_XREF", "STG_ECI_PTY_INACTIVE_STS",
                    "V_ECI_ETL_LU_DUP_CASES", "V_ECI_ETL_LU_FAMILY_VALIDATION"));

    /// @param duplicateCases `<source table>|<id>` of parties whose every case is a duplicate (reason 8)
    /// @param familyFlags    `<source table>|<id>` of family members with any family validation status
    public record Lookups(InactiveStatus.Lookup inactive, Map<String, Integer> hubStates, Set<String> duplicateCases,
            Set<String> familyFlags) {}

    public EciPartyValidation(EciQueries queries) {
        super(INFO, queries::fetchPartyNames, () -> new Lookups(
                new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())),
                LookupRows.toNumberMap(queries.fetchHubStates()),
                LookupRows.toMap(queries.fetchDuplicateCases()).keySet(),
                queries.fetchFamilyValidations().stream().filter(EciPartyValidation::flagged)
                        .map(f -> f.sourceTable() + "|" + f.idFamily()).collect(Collectors.toSet())));
    }

    static boolean flagged(FamilyValidation f) {
        return f.famNameStatus() != null || f.famPhoneAndAddressSts() != null || f.famInactiveSts() != null;
    }

    /// Party source key: the id left-padded to 10 digits, family members suffixed with `F`.
    public static String partyKey(String sourceTable, Object id) {
        return Infa.concat(lpad(id, 10, '0'), "ECI_FAMILY".equals(sourceTable) ? "F" : "");
    }

    @Override
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
        return InactiveStatus.output(changes, bad, EciTargets.InactiveStatus.class, EciTargets.InactiveStatus::new,
                EciTargets.InactiveLog.class, EciTargets.InactiveLog::new);
    }

    static boolean hasLength(String value) {
        return value != null && !value.stripTrailing().isEmpty();
    }
}
