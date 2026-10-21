package com.idq.cli.source.eci.etlmap.svc;

import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.substr;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.IdentifierRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.EciTargets;
import com.idq.cli.mdmdc.etldb.repo.EciAlternateIdRepository;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyIdentifier;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.eci.etldb.repo.EciChildDeltaRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveStatusRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` - ECI child / family ids, child SSN and Medicaid number.
/// See [docs/mappings/016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md].
@Service
public class EciAlternateIdService {

    public static final MappingInfo INFO = MappingInfo.of("016", "m_Tgt_C_S_ECI_Pty_Rle_Alt_Id", SourceSystem.ECI,
            List.of(EciTargets.AlternateId.class), List.of(EciSources.ChildDelta.class, EciSources.FamilyDelta.class,
            EciSources.MedicaidDelta.class, EciSources.SnCase.class, EciSources.InactiveStatus.class));

    private final EciChildDeltaRepository childDelta;
    private final EciInactiveStatusRepository inactiveStatuses;
    private final EciAlternateIdRepository alternateIds;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public EciAlternateIdService(EciChildDeltaRepository childDelta, EciInactiveStatusRepository inactiveStatuses,
            EciAlternateIdRepository alternateIds, BadRecordRepository badRecords, EtlSettings settings) {
        this.childDelta = childDelta;
        this.inactiveStatuses = inactiveStatuses;
        this.alternateIds = alternateIds;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// Child ids, child SSNs, Medicaid numbers and family ids, with their key already formulated.
    public List<PartyIdentifier> fetchPartyIdentifiers() {
        return childDelta.fetchPartyIdentifiers();
    }

    /// Parties deactivated by the validation mapping.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// Party key derived from the role key: its first 11 characters without a trailing `|`.
    public static String partyKey(String partyRoleFk) {
        var head = substr(partyRoleFk, 1, 11);
        return head == null ? null : head.replaceAll("\\|+$", "");
    }

    /// The key itself is formulated in the `IdqMapInitQuery`:
    /// `<party key>|Member|<type>|<id>` with `018` child id, `019` family id, `004` SSN (keyed by child id),
    /// `002` Medicaid (keyed by the Medicaid record id).
    public MappingOutput transform(List<PartyIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = new ArrayList<EciTargets.AlternateId>();
        var bad = new ArrayList<BadRecord>();
        for (var r : Rows.where(rows, r -> inactive.isActive(partyKey(r.ptyRelFk())))) {
            String value = r.altIdVal();
            switch (r.altIdTp()) {
                case "004" -> {
                    var ssn = IdentifierRules.ssn(r.altIdVal(), ctx);
                    if (ssn.invalid()) {
                        bad.add(exception(r, "ALT_ID_Type_SSN", ssn.exception(), ctx));
                        continue;
                    }
                    value = ssn.value();
                }
                case "002" -> {
                    var medicaid = IdentifierRules.medicaidId(r.altIdVal(), ctx);
                    if (medicaid.invalid()) {
                        bad.add(exception(r, "ALT_ID_TP_MedicaidId", medicaid.exception(), ctx));
                        continue;
                    }
                }
                case "018", "019" -> { }
                default -> {
                    continue;
                }
            }
            var audit = MdmAudit.srcRowid(pipe(Infa.toChar(r.id()), r.altIdTp())).periodStart(r.dateCreated())
                    .lastUpdated(ctx.runStart()).created(r.dateCreated()).hubState(1)
                    .sourceUpdated(Infa.nvl(r.dateModified(), r.dateCreated()));
            ids.add(new EciTargets.AlternateId(r.pkeySrcObject(), audit, new Columns.AlternateId(r.ptyRelFk(),
                    r.altIdTp(), value, "Issued", r.altIdTp(), null)));
        }
        return MappingOutput.empty().load(TargetBatch.replaceAll(EciTargets.AlternateId.class,
                Rows.lastPerKey(ids, EciTargets.AlternateId::pkeySrcObject))).reject(bad);
    }

    private static BadRecord exception(PartyIdentifier r, String attribute,
            com.idq.cli.core.reference.ExceptionInfo info, EtlContext ctx) {
        return ctx.badRecord().ids(r.pkeySrcObject(), r.ptyRelFk(), null).exception(info)
                .attribute(attribute, r.altIdVal()).build();
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(EciAlternateIdRepository.TABLE, replaceAlternateIds(output.rows(EciTargets.AlternateId.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceAlternateIds(List<EciTargets.AlternateId> rows) {
        settings.requireClearable(EciAlternateIdRepository.TABLE);
        alternateIds.deleteAll();
        return alternateIds.insertAll(rows).size();
    }
}
