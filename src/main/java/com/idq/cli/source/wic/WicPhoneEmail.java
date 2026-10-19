package com.idq.cli.source.wic;

import static com.idq.cli.core.EtlPatterns.badData4Email;
import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.write2TargetEmail;
import static com.idq.cli.core.EtlPatterns.write2TargetPhone;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

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
import com.idq.cli.source.wic.WicQueries.FamilyContact;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` - family phone and e-mail.
/// See [docs/mappings/033_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md].
@Component
public class WicPhoneEmail extends SourceMapping<FamilyContact, InactiveStatus.Lookup>
        implements MemberMapping.PhoneEmail<FamilyContact, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("033", "m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr",
            SourceSystem.WIC, List.of("C_S_WIC_PTY_RLE_PHN", "C_S_WIC_PTY_RLE_EADDR"), List.of(WicSources.EtlSrc.class,
            WicTargets.InactiveStatus.class));

    public WicPhoneEmail(WicQueries queries) {
        super(INFO, queries::fetchFamilyContacts,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    /// `<party>|Member|Telephone|001|<family id>|<number as reported, trimmed>`
    public static String phoneKey(FamilyContact c) {
        return pipe(memberRole(c.ptySrcKey()), "Telephone", "001", c.fid(), trim(c.phone()));
    }

    /// `<party>|Member|001|<family id>|<e-mail as reported>`
    public static String emailKey(FamilyContact c) {
        return pipe(memberRole(c.ptySrcKey()), "001", c.fid(), c.email());
    }

    @Override
    public MappingOutput transform(List<FamilyContact> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var phones = new ArrayList<WicTargets.Phone>();
        var emails = new ArrayList<WicTargets.Email>();
        var bad = new ArrayList<BadRecord>();
        for (var c : Rows.where(rows, c -> inactive.isActive(c.ptySrcKey()))) {
            var roleFk = memberRole(c.ptySrcKey());
            if (c.phone() != null) {
                var phone = ContactRules.phone(c.phone(), "WIC", "001", ctx);
                var code = phone.exception().code();
                if (code != null) {
                    bad.add(badData4Phone(ctx, c.ptySrcKey(), c.fid(), null, phone.value(), "001", "Primary",
                            c.datekey(), phone.exception(), "Bad Value"));
                }
                if (code == null || code.equals("Missing_AreaCode")) {
                    var key = phoneKey(c);
                    phones.add(write2TargetPhone(WicTargets.Phone::new, key, roleFk, "Telephone", "001",
                            phone.value(), "Primary", MdmAudit.srcRowid(key).periodStart(c.datekey())
                                    .lastUpdated(ctx.runStart()).hubState(1).sourceUpdated(c.datekey())));
                }
            }
            if (c.email() != null) {
                var email = ContactRules.email(c.email(), ctx);
                if (email.exception().configured()) {
                    bad.add(badData4Email(ctx, c.ptySrcKey(), c.fid(), c.email(), c.datekey(), email.exception()));
                } else {
                    var key = emailKey(c);
                    emails.add(write2TargetEmail(WicTargets.Email::new, key, roleFk, email.value(),
                            MdmAudit.srcRowid(key).periodStart(c.datekey()).lastUpdated(ctx.runStart())
                                    .created(ctx.runStart()).hubState(1).sourceUpdated(c.datekey())));
                }
            }
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(WicTargets.Phone.class,
                        Rows.lastPerKey(phones, WicTargets.Phone::pkeySrcObject)))
                .load(TargetBatch.replaceAll(WicTargets.Email.class,
                        Rows.lastPerKey(emails, WicTargets.Email::pkeySrcObject)))
                .reject(bad);
    }
}
