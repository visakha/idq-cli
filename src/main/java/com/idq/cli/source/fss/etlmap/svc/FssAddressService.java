package com.idq.cli.source.fss.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;
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
import com.idq.cli.mdmdc.etldb.models.FssTargets;
import com.idq.cli.mdmdc.etldb.repo.FssAddressRepository;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientAddress;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_FSS_Pty_Addr` - registration addresses (always physical mail, type `002`).
/// See [docs/mappings/021_m_Tgt_C_S_FSS_Pty_Addr.md].
@Service
public class FssAddressService {

    public static final MappingInfo INFO = MappingInfo.of("021", "m_Tgt_C_S_FSS_Pty_Addr", SourceSystem.FSS,
            List.of("C_S_FSS_PTY_RLE_ADDR", "DQM_ADDRESS"), List.of(FssSources.EtlSrc.class,
            FssSources.InactiveStatus.class));

    public static final String ADDRESS_TYPE = "002";

    private final AddressValidator validator;

    private final FssEtlSrcViewRepository etlSrc;
    private final FssInactiveStatusRepository inactiveStatuses;
    private final DqmAddressRepository dqmAddresses;
    private final FssAddressRepository addresses;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public FssAddressService(FssEtlSrcViewRepository etlSrc, FssInactiveStatusRepository inactiveStatuses,
            DqmAddressRepository dqmAddresses, FssAddressRepository addresses, BadRecordRepository badRecords,
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
    public List<ClientAddress> fetchClientAddresses() {
        return etlSrc.fetchClientAddresses();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// `<party key>|Member|002|<registration client id, 10 digits>|<LINE1>|<LINE2>|<CITY>|<STATE>|<zip>`
    public static String pkey(ClientAddress a) {
        return pipe(memberRole(a.ptySrcKey()), ADDRESS_TYPE, lpad(a.idRegistrationClient(), 10, '0'),
                trim(upper(a.addrLine1())), trim(upper(a.addrLine2())), upper(a.addrCity()), upper(a.addrState()),
                a.addrZip());
    }

    public MappingOutput transform(List<ClientAddress> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var candidates = Rows.where(rows, a -> inactive.isActive(a.ptySrcKey())).stream().map(a -> {
            var src = new Columns.SourceAddress(a.addrLine1(), a.addrLine2(), a.addrCity(), a.cdCnty(),
                    a.addrState(), "US", a.addrZip(), null);
            // the DQM party key repeats the ECI formula on the FSS client id
            return new AddressPatterns.Candidate(lpad(a.idClient(), 10, '0'), pkey(a), memberRole(a.ptySrcKey()),
                    ADDRESS_TYPE, ADDRESS_TYPE, src, a.addrZip(),
                    pipe(Infa.toChar(a.idClient()), Infa.toChar(a.idRegistrationClient())), a.dtCreated(),
                    a.dtLastUpdate(), a.dtLastUpdate(), a.idClient(), null, a.sourceType());
        }).toList();
        var routed = AddressPatterns.route(candidates, validator, ctx, FssTargets.Address::new);
        return MappingOutput.empty()
                .load(TargetBatch.append(DqmAddress.class, routed.dqm()))
                .load(TargetBatch.replaceAll(FssTargets.Address.class,
                        Rows.lastPerKey(routed.addresses(), FssTargets.Address::pkeySrcObject)))
                .reject(routed.exceptions());
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(DqmAddressRepository.TABLE, auditValidatedAddresses(output.rows(DqmAddress.class)));
        loaded.put(FssAddressRepository.TABLE, replaceAddresses(output.rows(FssTargets.Address.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int auditValidatedAddresses(List<DqmAddress> rows) {
        return dqmAddresses.insertAll(rows).size();
    }

    int replaceAddresses(List<FssTargets.Address> rows) {
        settings.requireClearable(FssAddressRepository.TABLE);
        addresses.deleteAll();
        return addresses.insertAll(rows).size();
    }
}
