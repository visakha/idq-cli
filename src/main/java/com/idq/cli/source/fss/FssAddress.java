package com.idq.cli.source.fss;

import static com.idq.cli.core.EtlPatterns.memberRole;
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
import com.idq.cli.source.fss.FssQueries.ClientAddress;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_FSS_Pty_Addr` - registration addresses (always physical mail, type `002`).
/// See [docs/mappings/021_m_Tgt_C_S_FSS_Pty_Addr.md].
@Component
public class FssAddress extends SourceMapping<ClientAddress, InactiveStatus.Lookup>
        implements MemberMapping.Address<ClientAddress, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("021", "m_Tgt_C_S_FSS_Pty_Addr", SourceSystem.FSS,
            List.of("C_S_FSS_PTY_RLE_ADDR", "DQM_ADDRESS"), List.of("V_FSS_ETL_SRC", "STG_FSS_PTY_INACTIVE_STS"));

    public static final String ADDRESS_TYPE = "002";

    private final AddressValidator validator;

    public FssAddress(FssQueries queries, AddressValidator validator) {
        super(INFO, queries::fetchClientAddresses,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
        this.validator = validator;
    }

    /// `<party key>|Member|002|<registration client id, 10 digits>|<LINE1>|<LINE2>|<CITY>|<STATE>|<zip>`
    public static String pkey(ClientAddress a) {
        return pipe(memberRole(a.ptySrcKey()), ADDRESS_TYPE, lpad(a.idRegistrationClient(), 10, '0'),
                trim(upper(a.addrLine1())), trim(upper(a.addrLine2())), upper(a.addrCity()), upper(a.addrState()),
                a.addrZip());
    }

    @Override
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
}
