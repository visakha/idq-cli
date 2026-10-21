package com.idq.cli.source.ttf.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.badData4Phone;
import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.write2TargetPhone;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.ContactRules;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientPhone;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import com.idq.cli.source.ttf.etldb.models.TtfTargets;
import com.idq.cli.source.ttf.etldb.repo.TtfEtlSrcViewRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfInactiveStatusRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfPhoneRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TTF_Pty_Rle_Phn` - client phone. See [docs/mappings/028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md].
@Service
public class TtfPhoneService {

    public static final MappingInfo INFO = MappingInfo.of("028", "m_Tgt_C_S_TTF_Pty_Rle_Phn", SourceSystem.TTF,
            List.of("C_S_TTF_PTY_RLE_PHN"), List.of(TtfSources.EtlSrc.class, TtfTargets.InactiveStatus.class));

    private final TtfEtlSrcViewRepository etlSrc;
    private final TtfInactiveStatusRepository inactiveStatuses;
    private final TtfPhoneRepository phones;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TtfPhoneService(TtfEtlSrcViewRepository etlSrc, TtfInactiveStatusRepository inactiveStatuses,
            TtfPhoneRepository phones, BadRecordRepository badRecords, EtlSettings settings) {
        this.etlSrc = etlSrc;
        this.inactiveStatuses = inactiveStatuses;
        this.phones = phones;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<ClientPhone> fetchClientPhones() {
        return etlSrc.fetchClientPhones();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// `<party>|Member|Telephone|001|<number as reported>`
    public static String pkey(String partyKey, String phone) {
        return pipe(memberRole(partyKey), "Telephone", "001", phone);
    }

    /// TTF reports no extension, so the extension rule never raises an exception.
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

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TtfPhoneRepository.TABLE, replacePhones(output.rows(TtfTargets.Phone.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replacePhones(List<TtfTargets.Phone> rows) {
        settings.requireClearable(TtfPhoneRepository.TABLE);
        phones.deleteAll();
        return phones.insertAll(rows).size();
    }
}
