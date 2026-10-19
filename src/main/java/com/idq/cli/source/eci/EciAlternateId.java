package com.idq.cli.source.eci;

import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.substr;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.IdentifierRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.eci.EciQueries.PartyIdentifier;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` - ECI child / family ids, child SSN and Medicaid number.
/// See [docs/mappings/016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md].
@Component
public class EciAlternateId extends SourceMapping<PartyIdentifier, InactiveStatus.Lookup>
        implements MemberMapping.AlternateId<PartyIdentifier, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("016", "m_Tgt_C_S_ECI_Pty_Rle_Alt_Id", SourceSystem.ECI,
            List.of("C_S_ECI_PTY_RLE_ALT_ID"), List.of("STG_ECI_D_CHILD", "STG_ECI_D_FAMILY", "STG_ECI_D_MEDICAID",
                    "STG_ECI_SN_CASE", "STG_ECI_PTY_INACTIVE_STS"));

    public EciAlternateId(EciQueries queries) {
        super(INFO, queries::fetchPartyIdentifiers,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    /// Party key derived from the role key: its first 11 characters without a trailing `|`.
    public static String partyKey(String partyRoleFk) {
        var head = substr(partyRoleFk, 1, 11);
        return head == null ? null : head.replaceAll("\\|+$", "");
    }

    /// The key itself is formulated in the `IdqMapInitQuery`:
    /// `<party key>|Member|<type>|<id>` with `018` child id, `019` family id, `004` SSN (keyed by child id),
    /// `002` Medicaid (keyed by the Medicaid record id).
    @Override
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
}
