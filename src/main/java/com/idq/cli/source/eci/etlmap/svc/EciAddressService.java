package com.idq.cli.source.eci.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.concat;
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
import com.idq.cli.mdmdc.etldb.models.EciTargets;
import com.idq.cli.mdmdc.etldb.repo.EciAddressRepository;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyAddress;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.eci.etldb.repo.EciFamilyAddressViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveStatusRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_ECI_Pty_Addr` - family addresses. See [docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md].
///
/// Read the addresses and the deactivated parties, drop the addresses of deactivated parties and validate the rest
/// ([#transform]), then audit them to `DQM_ADDRESS` and replace `C_S_ECI_PTY_RLE_ADDR` ([#load]). Registered with the
/// workflow runner in [EciMappings].
@Service
public class EciAddressService {

    public static final MappingInfo INFO = MappingInfo.of("015", "m_Tgt_C_S_ECI_Pty_Addr", SourceSystem.ECI,
            List.of(EciTargets.Address.class, DqmAddress.class), List.of(EciSources.EtlSrcFamilyAddress.class,
            EciSources.InactiveStatus.class));

    private final EciFamilyAddressViewRepository familyAddresses;
    private final EciInactiveStatusRepository inactiveStatuses;
    private final EciAddressRepository addresses;
    private final DqmAddressRepository dqmAddresses;
    private final BadRecordRepository badRecords;
    private final AddressValidator validator;
    private final EtlSettings settings;

    public EciAddressService(EciFamilyAddressViewRepository familyAddresses,
            EciInactiveStatusRepository inactiveStatuses, EciAddressRepository addresses,
            DqmAddressRepository dqmAddresses, BadRecordRepository badRecords, AddressValidator validator,
            EtlSettings settings) {
        this.familyAddresses = familyAddresses;
        this.inactiveStatuses = inactiveStatuses;
        this.addresses = addresses;
        this.dqmAddresses = dqmAddresses;
        this.badRecords = badRecords;
        this.validator = validator;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`: child and family addresses.
    public List<FamilyAddress> fetchFamilyAddresses() {
        return familyAddresses.fetchFamilyAddresses();
    }

    /// Parties deactivated by the validation mapping (013); their addresses are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// `<party key>|Member|<MDM address type>|<address id, 10 digits>|<LINE1>|<LINE2>|<CITY>|<STATE>|<zip>|<zip4>`
    public static String pkey(FamilyAddress a, String addressTypeMaster) {
        return pipe(memberRole(EciPartyValidationService.partyKey(a.sourceTable(), a.id())), addressTypeMaster,
                lpad(a.idFamilyAddress(), 10, '0'), trim(upper(a.address1())), trim(upper(a.address2())),
                upper(a.cityName()), upper(a.stateAbbrev()), a.zipCode(), a.zipSfx());
    }

    public MappingOutput transform(List<FamilyAddress> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var candidates = rows.stream()
                .filter(a -> inactive.isActive(EciPartyValidationService.partyKey(a.sourceTable(), a.id())))
                .map(a -> {
                    var type = ctx.reference().masterCode("ADDR_TP", "ECI", a.addressCd()).orElse(null);
                    var partyKey = EciPartyValidationService.partyKey(a.sourceTable(), a.id());
                    var src = new Columns.SourceAddress(a.address1(), a.address2(), a.cityName(), a.countyName(),
                            a.stateAbbrev(), "US", a.zipCode(), a.zipSfx());
                    return new AddressPatterns.Candidate(partyKey, pkey(a, type), memberRole(partyKey), type,
                            a.addressCd(), src, concat(a.zipCode(), a.zipSfx() == null ? "" : "-" + a.zipSfx()),
                            pipe(Infa.toChar(a.id()), Infa.toChar(a.idFamilyAddress())), a.lastUpdateDate(),
                            a.lastUpdateDate(), a.lastUpdateDate(), a.id(), a.idFamilyAddress(), a.sourceTable());
                }).toList();
        var routed = AddressPatterns.route(candidates, validator, ctx, EciTargets.Address::new);
        return MappingOutput.empty()
                .load(TargetBatch.append(DqmAddress.class, routed.dqm()))
                .load(TargetBatch.append(EciTargets.Address.class,
                        Rows.lastPerKey(routed.addresses(), EciTargets.Address::pkeySrcObject)))
                .reject(routed.exceptions());
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(DqmAddressRepository.TABLE, auditValidatedAddresses(output.rows(DqmAddress.class)));
        loaded.put(EciAddressRepository.TABLE, insertAddresses(output.rows(EciTargets.Address.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int auditValidatedAddresses(List<DqmAddress> rows) {
        return dqmAddresses.insertAll(rows).size();
    }

    int insertAddresses(List<EciTargets.Address> rows) {
        return addresses.insertAll(rows).size();
    }
}
