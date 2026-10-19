package com.idq.cli.source.eci;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.trim;
import static com.idq.cli.core.Infa.upper;

import com.idq.cli.core.AddressPatterns;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.rules.AddressValidator;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.DqmAddress;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.eci.EciQueries.FamilyAddress;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_ECI_Pty_Addr` - family addresses. See [docs/mappings/015_m_Tgt_C_S_ECI_Pty_Addr.md].
@Component
public class EciAddress extends SourceMapping<FamilyAddress, InactiveStatus.Lookup>
        implements MemberMapping.Address<FamilyAddress, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("015", "m_Tgt_C_S_ECI_Pty_Addr", SourceSystem.ECI,
            List.of("C_S_ECI_PTY_RLE_ADDR", "DQM_ADDRESS"), List.of(EciSources.EtlSrcFamilyAddress.class,
            EciTargets.InactiveStatus.class));

    private final AddressValidator validator;

    public EciAddress(EciQueries queries, AddressValidator validator) {
        super(INFO, queries::fetchFamilyAddresses,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
        this.validator = validator;
    }

    /// `<party key>|Member|<MDM address type>|<address id, 10 digits>|<LINE1>|<LINE2>|<CITY>|<STATE>|<zip>|<zip4>`
    public static String pkey(FamilyAddress a, String addressTypeMaster) {
        return pipe(memberRole(EciPartyValidation.partyKey(a.sourceTable(), a.id())), addressTypeMaster,
                lpad(a.idFamilyAddress(), 10, '0'), trim(upper(a.address1())), trim(upper(a.address2())),
                upper(a.cityName()), upper(a.stateAbbrev()), a.zipCode(), a.zipSfx());
    }

    @Override
    public MappingOutput transform(List<FamilyAddress> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var candidates = rows.stream()
                .filter(a -> inactive.isActive(EciPartyValidation.partyKey(a.sourceTable(), a.id())))
                .map(a -> {
                    var type = ctx.reference().masterCode("ADDR_TP", "ECI", a.addressCd()).orElse(null);
                    var partyKey = EciPartyValidation.partyKey(a.sourceTable(), a.id());
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
                .load(TargetBatch.replaceAll(EciTargets.Address.class,
                        Rows.lastPerKey(routed.addresses(), EciTargets.Address::pkeySrcObject)))
                .reject(routed.exceptions());
    }
}
