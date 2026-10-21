package com.idq.cli.source.eci.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.badData4Email;
import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.write2TargetEmail;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.ContactRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.EciTargets;
import com.idq.cli.mdmdc.etldb.repo.EciEmailRepository;
import com.idq.cli.mdmdc.etldb.repo.EciPhoneRepository;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyContact;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.eci.etldb.repo.EciFamilyPhoneViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveStatusRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` - family phones and e-mail addresses.
/// See [docs/mappings/017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md].
@Service
public class EciPhoneEmailService {

    public static final MappingInfo INFO = MappingInfo.of("017", "m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr",
            SourceSystem.ECI, List.of("C_S_ECI_PTY_RLE_PHN", "C_S_ECI_PTY_RLE_EADDR"),
            List.of(EciSources.EtlSrcFamilyPhone.class, EciSources.InactiveStatus.class));

    private final EciFamilyPhoneViewRepository familyPhones;
    private final EciInactiveStatusRepository inactiveStatuses;
    private final EciPhoneRepository phones;
    private final EciEmailRepository emails;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public EciPhoneEmailService(EciFamilyPhoneViewRepository familyPhones,
            EciInactiveStatusRepository inactiveStatuses, EciPhoneRepository phones, EciEmailRepository emails,
            BadRecordRepository badRecords, EtlSettings settings) {
        this.familyPhones = familyPhones;
        this.inactiveStatuses = inactiveStatuses;
        this.phones = phones;
        this.emails = emails;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// Child and family phones and e-mail addresses.
    public List<FamilyContact> fetchFamilyContacts() {
        return familyPhones.fetchFamilyContacts();
    }

    /// Parties deactivated by the validation mapping.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
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

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(EciPhoneRepository.TABLE, replacePhones(output.rows(EciTargets.Phone.class)));
        loaded.put(EciEmailRepository.TABLE, replaceEmails(output.rows(EciTargets.Email.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replacePhones(List<EciTargets.Phone> rows) {
        settings.requireClearable(EciPhoneRepository.TABLE);
        phones.deleteAll();
        return phones.insertAll(rows).size();
    }

    int replaceEmails(List<EciTargets.Email> rows) {
        settings.requireClearable(EciEmailRepository.TABLE);
        emails.deleteAll();
        return emails.insertAll(rows).size();
    }
}
