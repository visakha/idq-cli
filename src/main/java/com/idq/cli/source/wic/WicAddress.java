package com.idq.cli.source.wic;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.lpad;
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
import com.idq.cli.source.wic.WicQueries.FamilyAddress;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_WIC_Pty_Addr` - family addresses (physical mail `002`, state Texas).
/// See [docs/mappings/031_m_Tgt_C_S_WIC_Pty_Addr.md].
@Component
public class WicAddress extends SourceMapping<FamilyAddress, InactiveStatus.Lookup>
        implements MemberMapping.Address<FamilyAddress, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("031", "m_Tgt_C_S_WIC_Pty_Addr", SourceSystem.WIC,
            List.of("C_S_WIC_PTY_RLE_ADDR", "DQM_ADDRESS"), List.of("V_WIC_ETL_SRC", "STG_WIC_PTY_INACTIVE_STS"));

    public static final String ADDRESS_TYPE = "002";

    private final AddressValidator validator;

    public WicAddress(WicQueries queries, AddressValidator validator) {
        super(INFO, queries::fetchFamilyAddresses,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
        this.validator = validator;
    }

    /// `<party key>|Member|002|<family id, 12 digits>|<LINE1>|<LINE2>|<CITY>||<zip>` - the state segment is
    /// empty in the IDQ expression.
    public static String pkey(FamilyAddress a) {
        return concat(memberRole(a.ptySrcKey()), "|", ADDRESS_TYPE, "|", lpad(a.fid(), 12, '0'), "|",
                trim(upper(a.address1())), "|", trim(upper(a.address2())), "|", upper(a.city()), "|", "|",
                a.zipCode());
    }

    @Override
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
}
