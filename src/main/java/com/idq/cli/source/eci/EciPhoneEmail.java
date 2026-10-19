package com.idq.cli.source.eci;

import static com.idq.cli.core.EtlPatterns.badData4Email;
import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.write2TargetEmail;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.ContactRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.eci.EciQueries.FamilyContact;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` - family phones and e-mail addresses.
/// See [docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md].
@Component
public class EciPhoneEmail extends SourceMapping<FamilyContact, InactiveStatus.Lookup>
        implements MemberMapping.PhoneEmail<FamilyContact, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("017", "m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr",
            SourceSystem.ECI, List.of("C_S_ECI_PTY_RLE_PHN", "C_S_ECI_PTY_RLE_EADDR"),
            List.of("V_ECI_ETL_SRC_FAMILY_PHONE", "STG_ECI_PTY_INACTIVE_STS"));

    public EciPhoneEmail(EciQueries queries) {
        super(INFO, queries::fetchFamilyContacts,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    /// The view id as-is plus `F` for family members (no padding in this mapping).
    public static String partyKey(FamilyContact c) {
        return concat(c.id(), "ECI_FAMILY".equals(c.sourceTable()) ? "F" : "");
    }

    /// E-mail: `<party>|Member|001|<phone row id>|<e-mail>`;
    /// phone: `<party>|Member|<phone type>|<usage>|<phone row id>|<number as reported>`.
    public static String pkey(FamilyContact c) {
        return "EADDRESS".equals(c.phoneEmailType())
                ? pipe(partyKey(c), "Member", "001", c.idFamilyPhone(), trim(c.phoneEmail()))
                : pipe(partyKey(c), "Member", c.phoneTp(), c.usgTp(), c.idFamilyPhone(), trim(c.phoneEmail()));
    }

    @Override
    public MappingOutput transform(List<FamilyContact> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var phones = new ArrayList<EciTargets.Phone>();
        var emails = new ArrayList<EciTargets.Email>();
        var bad = new ArrayList<BadRecord>();
        for (var c : Rows.where(rows, c -> inactive.isActive(partyKey(c)))) {
            var key = pkey(c);
            var roleFk = partyKey(c) + "|Member";
            var audit = MdmAudit.srcRowid(srcRowid(c)).periodStart(c.periodStartDate()).lastUpdated(ctx.runStart())
                    .created(ctx.runStart()).hubState(1).sourceUpdated(c.periodStartDate());
            if ("EADDRESS".equals(c.phoneEmailType())) {
                var email = ContactRules.email(c.phoneEmail(), ctx);
                if (email.exception().configured()) {
                    bad.add(badData4Email(ctx, c.idFamilyPhone(), null, c.phoneEmail(), c.periodStartDate(),
                            email.exception()));
                } else {
                    emails.add(write2TargetEmail(EciTargets.Email::new, key, roleFk, email.value(),
                            MdmAudit.srcRowid(key).periodStart(c.periodStartDate()).lastUpdated(ctx.runStart())
                                    .created(ctx.runStart()).hubState(1).sourceUpdated(c.periodStartDate())));
                }
                continue;
            }
            var number = c.phoneEmail() != null && c.phoneEmail().length() == 7 ? "000" + c.phoneEmail()
                    : c.phoneEmail();
            var phone = ContactRules.phone(number, "ECI", c.usgTp(), ctx);
            var code = phone.exception().code();
            if (code != null) {
                bad.add(badData4Phone(ctx, null, c.idCase(), c.usgTp(), phone.value(), c.usgTp(), c.prefLvl(),
                        c.periodStartDate(), phone.exception(), "Bad Value"));
            }
            if (code == null || code.equals("Missing_AreaCode")) {
                phones.add(new EciTargets.Phone(key, audit, new Columns.Phone(roleFk, c.phoneTp(), c.usgTp(),
                        phone.value(), c.prefLvl()), c.workExt()));
            }
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(EciTargets.Phone.class,
                        Rows.lastPerKey(phones, EciTargets.Phone::pkeySrcObject)))
                .load(TargetBatch.replaceAll(EciTargets.Email.class,
                        Rows.lastPerKey(emails, EciTargets.Email::pkeySrcObject)))
                .reject(bad);
    }

    /// Like the key but with the number untrimmed.
    static String srcRowid(FamilyContact c) {
        return "EADDRESS".equals(c.phoneEmailType())
                ? pipe(partyKey(c), "Member", "001", c.idFamilyPhone(), c.phoneEmail())
                : pipe(partyKey(c), "Member", c.phoneTp(), c.usgTp(), c.idFamilyPhone(), c.phoneEmail());
    }
}
