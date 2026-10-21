package com.idq.cli.source.fss.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.badData4Email;
import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.write2TargetEmail;
import static com.idq.cli.core.Infa.lpad;
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
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientContact;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.models.FssTargets;
import com.idq.cli.source.fss.etldb.repo.FssEmailRepository;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import com.idq.cli.source.fss.etldb.repo.FssPhoneRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` - registration phone (with extension) and e-mail.
/// See [docs/mappings/023_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md].
@Service
public class FssPhoneEmailService {

    public static final MappingInfo INFO = MappingInfo.of("023", "m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr",
            SourceSystem.FSS, List.of("C_S_FSS_PTY_RLE_PHN", "C_S_FSS_PTY_RLE_EADDR"), List.of(FssSources.EtlSrc.class,
            FssTargets.InactiveStatus.class));

    private final FssEtlSrcViewRepository etlSrc;
    private final FssInactiveStatusRepository inactiveStatuses;
    private final FssPhoneRepository phones;
    private final FssEmailRepository emails;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public FssPhoneEmailService(FssEtlSrcViewRepository etlSrc, FssInactiveStatusRepository inactiveStatuses,
            FssPhoneRepository phones, FssEmailRepository emails, BadRecordRepository badRecords,
            EtlSettings settings) {
        this.etlSrc = etlSrc;
        this.inactiveStatuses = inactiveStatuses;
        this.phones = phones;
        this.emails = emails;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<ClientContact> fetchClientContacts() {
        return etlSrc.fetchClientContacts();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// `<party>|Member|Telephone|001|<registration client id, 10 digits>|<number as reported>`
    public static String phoneKey(ClientContact c) {
        return pipe(memberRole(c.ptySrcKey()), "Telephone", "001", lpad(c.idRegistrationClient(), 10, '0'),
                trim(c.nbrPhone()));
    }

    /// `<party>|Member|001|<registration client id, 10 digits>|<e-mail as reported>`
    public static String emailKey(ClientContact c) {
        return pipe(memberRole(c.ptySrcKey()), "001", lpad(c.idRegistrationClient(), 10, '0'), trim(c.addrEmail()));
    }

    public MappingOutput transform(List<ClientContact> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var phones = new ArrayList<FssTargets.Phone>();
        var emails = new ArrayList<FssTargets.Email>();
        var bad = new ArrayList<BadRecord>();
        for (var c : Rows.where(rows, c -> inactive.isActive(c.ptySrcKey()))) {
            var roleFk = memberRole(c.ptySrcKey());
            if (c.nbrPhone() != null) {
                var phone = ContactRules.phone(c.nbrPhone(), "FSS", "001", ctx);
                var ext = ContactRules.phoneExtension(c.nbrPhoneExt(), ctx);
                if (phone.invalid()) {
                    bad.add(badData4Phone(ctx, null, c.idRegistrationClient(), null, phone.value(), "001", "Primary",
                            c.dtLastUpdate(), phone.exception(), "Rejected Record"));
                } else {
                    var key = phoneKey(c);
                    var audit = MdmAudit.srcRowid(key).periodStart(c.dtLastUpdate()).lastUpdated(ctx.runStart())
                            .hubState(1).sourceUpdated(c.dtLastUpdate());
                    phones.add(new FssTargets.Phone(key, audit, new Columns.Phone(roleFk, "Telephone", "001",
                            phone.value(), "Primary"), ext.invalid() ? "" : ext.value()));
                }
                if (ext.invalid()) {
                    bad.add(ctx.badRecord().ids(null, c.idRegistrationClient(), null).exception(ext.exception())
                            .exceptionType("Bad Value").attribute("Main Phone Ext", ext.value())
                            .phones(ext.value(), null, null).period(c.dtLastUpdate(), null).build());
                }
            }
            if (c.addrEmail() != null) {
                var email = ContactRules.email(c.addrEmail(), ctx);
                if (email.exception().configured()) {
                    bad.add(badData4Email(ctx, c.ptySrcKey(), c.idRegistrationClient(), c.addrEmail(),
                            c.dtLastUpdate(), email.exception()));
                } else {
                    var key = emailKey(c);
                    emails.add(write2TargetEmail(FssTargets.Email::new, key, roleFk, email.value(),
                            MdmAudit.srcRowid(key).periodStart(c.dtLastUpdate()).lastUpdated(ctx.runStart())
                                    .created(ctx.runStart()).hubState(1).sourceUpdated(c.dtLastUpdate())));
                }
            }
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(FssTargets.Phone.class,
                        Rows.lastPerKey(phones, FssTargets.Phone::pkeySrcObject)))
                .load(TargetBatch.replaceAll(FssTargets.Email.class,
                        Rows.lastPerKey(emails, FssTargets.Email::pkeySrcObject)))
                .reject(bad);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(FssPhoneRepository.TABLE, replacePhones(output.rows(FssTargets.Phone.class)));
        loaded.put(FssEmailRepository.TABLE, replaceEmails(output.rows(FssTargets.Email.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replacePhones(List<FssTargets.Phone> rows) {
        settings.requireClearable(FssPhoneRepository.TABLE);
        phones.deleteAll();
        return phones.insertAll(rows).size();
    }

    int replaceEmails(List<FssTargets.Email> rows) {
        settings.requireClearable(FssEmailRepository.TABLE);
        emails.deleteAll();
        return emails.insertAll(rows).size();
    }
}
