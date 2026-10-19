package com.idq.cli.source.ttf;

import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.write2TargetPhone;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.ContactRules;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.ttf.TtfQueries.ClientPhone;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TTF_Pty_Rle_Phn` - client phone. See [docs/mappings/028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md].
@Component
public class TtfPhone extends SourceMapping<ClientPhone, InactiveStatus.Lookup>
        implements MemberMapping.PhoneEmail<ClientPhone, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("028", "m_Tgt_C_S_TTF_Pty_Rle_Phn", SourceSystem.TTF,
            List.of("C_S_TTF_PTY_RLE_PHN"), List.of(TtfSources.EtlSrc.class, TtfTargets.InactiveStatus.class));

    public TtfPhone(TtfQueries queries) {
        super(INFO, queries::fetchClientPhones,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    /// `<party>|Member|Telephone|001|<number as reported>`
    public static String pkey(String partyKey, String phone) {
        return pipe(memberRole(partyKey), "Telephone", "001", phone);
    }

    /// TTF reports no extension, so the extension rule never raises an exception.
    @Override
    public MappingOutput transform(List<ClientPhone> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var phones = new ArrayList<TtfTargets.Phone>();
        var bad = new ArrayList<BadRecord>();
        for (var r : Rows.where(rows, r -> inactive.isActive(r.ptySrcKey()) && r.phone() != null)) {
            var phone = ContactRules.phone(r.phone(), "TTF", "001", ctx);
            if (phone.invalid()) {
                bad.add(badData4Phone(ctx, null, null, null, phone.value(), "001", "Primary", r.submitdate(),
                        phone.exception(), "Rejected Record"));
                continue;
            }
            var key = pkey(r.ptySrcKey(), r.phone());
            phones.add(write2TargetPhone(TtfTargets.Phone::new, key, memberRole(r.ptySrcKey()), "Telephone", "001",
                    phone.value(), "Primary", MdmAudit.srcRowid(key).periodStart(r.submitdate())
                            .lastUpdated(ctx.runStart()).hubState(1).sourceUpdated(r.submitdate())));
        }
        return MappingOutput.empty().load(TargetBatch.replaceAll(TtfTargets.Phone.class,
                Rows.lastPerKey(phones, TtfTargets.Phone::pkeySrcObject))).reject(bad);
    }
}
