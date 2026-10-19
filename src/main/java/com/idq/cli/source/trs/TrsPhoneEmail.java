package com.idq.cli.source.trs;

import static com.idq.cli.core.EtlPatterns.badData4Email;
import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.write2TargetEmail;
import static com.idq.cli.core.EtlPatterns.write2TargetPhone;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.rtrim;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.ReferenceData.CodeValue;
import com.idq.cli.core.rules.ContactRules;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.CaseContact;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` - case phones and e-mail applied to every individual of the case.
/// See [docs/mappings/006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md].
@Component
public class TrsPhoneEmail extends SourceMapping<CaseContact, NoLookups>
        implements MemberMapping.PhoneEmail<CaseContact, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("006", "m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr",
            SourceSystem.TRS, List.of("C_S_TRS_PTY_RLE_PHN", "C_S_TRS_PTY_RLE_EADDR"),
            List.of("STG_TRS_D_DC_CASES", "STG_TRS_DC_CASE_INDV", "STG_TRS_VALID_MEMBERS"));

    public static final String TELEPHONE = "Telephone";

    public TrsPhoneEmail(TrsQueries queries) {
        super(INFO, queries::fetchCaseContacts, NoLookups::none);
    }

    /// `<indv id>|Member|Telephone|<usage master code>|<standardized number>`
    public static String phoneKey(String partyKey, String usageMasterCode, String phone) {
        return pipe(memberRole(partyKey), TELEPHONE, usageMasterCode, phone);
    }

    /// `<indv id>|Member|001|<e-mail as reported>`
    public static String emailKey(Long indvId, String email) {
        return concat(indvId, "|Member|", "001", "|", email);
    }

    /// `mplt_Member_Pty_Rle_Phn_Normalization`: main (`001`), work with extension (`002`) and other (`003`) numbers.
    record PhoneSlot(CaseContact src, String preference, String usageType, String number) {}

    static Stream<PhoneSlot> phoneSlots(CaseContact r) {
        var work = r.workPhNum() == null ? null : rtrim(concat(r.workPhNum(), " ", r.workPhNumExt()));
        return Stream.of(new PhoneSlot(r, "Primary", "001", r.phNum()), new PhoneSlot(r, "Secondary", "002", work),
                new PhoneSlot(r, "Tertiary", "003", r.otherPhNum()));
    }

    @Override
    public MappingOutput transform(List<CaseContact> rows, NoLookups lookups, EtlContext ctx) {
        var phones = new ArrayList<TrsTargets.Phone>();
        var emails = new ArrayList<TrsTargets.Email>();
        var bad = new ArrayList<BadRecord>();

        rows.stream().flatMap(TrsPhoneEmail::phoneSlots).forEach(slot -> {
            // the normalizer calls rule_Phone_Std without source system or usage type
            var phone = ContactRules.phone(slot.number(), null, null, ctx);
            if (phone.value() == null) {
                return;
            }
            var r = slot.src();
            if (phone.invalid()) {
                bad.add(badData4Phone(ctx, r.ptyPk(), r.caseNum(), slot.usageType(), phone.value(),
                        slot.usageType(), slot.preference(), r.createDt(), phone.exception(), "Bad Value"));
                return;
            }
            var usage = ctx.reference().codeValueByMaster("PHN_USG_TP", "TRS", slot.usageType())
                    .map(CodeValue::mstrRefCode).orElse(null);
            var key = phoneKey(r.ptyPk(), usage, phone.value());
            phones.add(write2TargetPhone(TrsTargets.Phone::new, key, memberRole(r.ptyPk()), TELEPHONE,
                    slot.usageType(), phone.value(), slot.preference(), audit(key, r, ctx)));
        });

        Rows.where(rows, r -> trim(r.email()) != null).forEach(r -> {
            var email = ContactRules.email(r.email(), ctx);
            if (email.exception().configured()) {
                bad.add(badData4Email(ctx, Infa.toChar(r.indvId()), r.caseNum(), r.email(), r.createDt(),
                        email.exception()));
                return;
            }
            var key = emailKey(r.indvId(), r.email());
            emails.add(write2TargetEmail(TrsTargets.Email::new, key, memberRole(r.ptyPk()), email.value(),
                    audit(key, r, ctx)));
        });

        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(TrsTargets.Phone.class, Rows.latestPerKey(phones)))
                .load(TargetBatch.replaceAll(TrsTargets.Email.class, Rows.latestPerKey(emails)))
                .reject(bad);
    }

    private static MdmAudit audit(String key, CaseContact r, EtlContext ctx) {
        return MdmAudit.srcRowid(key).periodStart(r.createDt()).lastUpdated(ctx.runStart()).created(r.createDt())
                .sourceUpdated(r.createDt());
    }
}
