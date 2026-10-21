package com.idq.cli.source.wic.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.trim;
import static com.idq.cli.core.Infa.upper;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.AddressPatterns;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.AddressValidator;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.DqmAddress;
import com.idq.cli.core.target.DqmAddressRepository;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.WicTargets;
import com.idq.cli.mdmdc.etldb.repo.WicAddressRepository;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyAddress;
import com.idq.cli.source.wic.etldb.models.WicSources;
import com.idq.cli.source.wic.etldb.repo.WicEtlSrcViewRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveStatusRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_WIC_Pty_Addr` - family addresses (physical mail `002`, state Texas).
/// See [docs/mappings/031_m_Tgt_C_S_WIC_Pty_Addr.md].
@Service
public class WicAddressService {

    public static final MappingInfo INFO = MappingInfo.of("031", "m_Tgt_C_S_WIC_Pty_Addr", SourceSystem.WIC,
            List.of("C_S_WIC_PTY_RLE_ADDR", "DQM_ADDRESS"), List.of(WicSources.EtlSrc.class,
            WicSources.InactiveStatus.class));

    public static final String ADDRESS_TYPE = "002";

    private final AddressValidator validator;

    private final WicEtlSrcViewRepository etlSrc;
    private final WicInactiveStatusRepository inactiveStatuses;
    private final DqmAddressRepository dqmAddresses;
    private final WicAddressRepository addresses;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public WicAddressService(WicEtlSrcViewRepository etlSrc, WicInactiveStatusRepository inactiveStatuses,
            DqmAddressRepository dqmAddresses, WicAddressRepository addresses, BadRecordRepository badRecords,
            AddressValidator validator, EtlSettings settings) {
        this.etlSrc = etlSrc;
        this.inactiveStatuses = inactiveStatuses;
        this.dqmAddresses = dqmAddresses;
        this.addresses = addresses;
        this.badRecords = badRecords;
        this.settings = settings;
        this.validator = validator;
    }

    /// The `IdqMapInitQuery`.
    public List<FamilyAddress> fetchFamilyAddresses() {
        return etlSrc.fetchFamilyAddresses();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// `<party key>|Member|002|<family id, 12 digits>|<LINE1>|<LINE2>|<CITY>||<zip>` - the state segment is
    /// empty in the IDQ expression.
    public static String pkey(FamilyAddress a) {
        return concat(memberRole(a.ptySrcKey()), "|", ADDRESS_TYPE, "|", lpad(a.fid(), 12, '0'), "|",
                trim(upper(a.address1())), "|", trim(upper(a.address2())), "|", upper(a.city()), "|", "|",
                a.zipCode());
    }

    public MappingOutput transform(List<FamilyAddress> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var candidates = Rows.where(rows, a -> inactive.isActive(a.ptySrcKey())).stream().map(a -> {
            var src = new Columns.SourceAddress(a.address1(), a.address2(), a.city(), a.county(), "TX", "US",
                    a.zipCode(), null);
            return new AddressPatterns.Candidate(lpad(a.id(), 10, '0'), pkey(a), memberRole(a.ptySrcKey()),
                    ADDRESS_TYPE, ADDRESS_TYPE, src, a.zipCode(), Infa.pipe(a.id(), a.fid()),
                    a.dateAddressValidFrom(), a.dateAddressValidFrom(), a.dateAddressValidFrom(), a.id(), a.fid(),
                    a.sourceTable());
        }).toList();
        var routed = AddressPatterns.route(candidates, validator, ctx, WicTargets.Address::new);
        return MappingOutput.empty()
                .load(TargetBatch.append(DqmAddress.class, routed.dqm()))
                .load(TargetBatch.replaceAll(WicTargets.Address.class,
                        Rows.lastPerKey(routed.addresses(), WicTargets.Address::pkeySrcObject)))
                .reject(routed.exceptions());
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(DqmAddressRepository.TABLE, auditValidatedAddresses(output.rows(DqmAddress.class)));
        loaded.put(WicAddressRepository.TABLE, replaceAddresses(output.rows(WicTargets.Address.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int auditValidatedAddresses(List<DqmAddress> rows) {
        return dqmAddresses.insertAll(rows).size();
    }

    int replaceAddresses(List<WicTargets.Address> rows) {
        settings.requireClearable(WicAddressRepository.TABLE);
        addresses.deleteAll();
        return addresses.insertAll(rows).size();
    }
}
