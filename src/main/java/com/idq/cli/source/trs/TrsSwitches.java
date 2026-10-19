package com.idq.cli.source.trs;

import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.MemberSwitches;
import java.util.List;
import java.util.stream.Stream;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` - TIERS switches as managed attributes.
/// See [docs/mappings/007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md].
@Component
public class TrsSwitches extends SourceMapping<MemberSwitches, NoLookups>
        implements MemberMapping.ManagedAttribute<MemberSwitches, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("007", "m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw", SourceSystem.TRS,
            List.of("C_S_TRS_PTY_MNG_ATTR"), List.of(TrsSources.DDcIndv.class, TrsSources.DCvDcMciIndv.class,
            TrsTargets.ValidMember.class));

    public TrsSwitches(TrsQueries queries) {
        super(INFO, queries::fetchMemberSwitches, NoLookups::none);
    }

    /// `<party key>|<attribute type>`
    public static String pkey(String partyKey, String attributeType) {
        return pipe(partyKey, attributeType);
    }

    record Attribute(String type, String value) {}

    /// `nrm_Attribute_Types`: five attributes per member, in normalizer order.
    static Stream<Attribute> attributes(MemberSwitches r) {
        return Stream.of(new Attribute("File_Clearance_SW", r.fileClearanceSw()),
                new Attribute("SSA_Validation_SW", r.ssaValidationSw()),
                new Attribute("TW_Convert_Ind", r.twConvertInd()),
                new Attribute("LTC_Convert_Ind", r.ltcConvertInd()),
                new Attribute("Source_Table", r.srcTbl()));
    }

    /// Blank attributes are dropped. The table is emptied first; mapping 002 then adds the authorized
    /// representative flags.
    @Override
    public MappingOutput transform(List<MemberSwitches> rows, NoLookups lookups, EtlContext ctx) {
        var attributes = rows.stream().flatMap(r -> attributes(r).filter(a -> Infa.hasText(a.value())).map(a -> {
            var key = pkey(r.ptyPk(), a.type());
            var audit = MdmAudit.srcRowid(key).periodStart(r.effBeginDt()).lastUpdated(ctx.runStart())
                    .created(ctx.runStart()).sourceUpdated(r.createDt());
            return new TrsTargets.ManagedAttribute(key, audit,
                    new Columns.ManagedAttribute(r.ptyPk(), a.type(), a.value()));
        })).toList();
        var ordered = Rows.sorted(Rows.distinct(attributes),
                Rows.<TrsTargets.ManagedAttribute, String>asc(TrsTargets.ManagedAttribute::pkeySrcObject)
                        .thenComparing(Rows.asc(m -> m.audit().periodStartDate())));
        return MappingOutput.empty().load(TargetBatch.replaceAll(TrsTargets.ManagedAttribute.class,
                Rows.lastPerKey(ordered, TrsTargets.ManagedAttribute::pkeySrcObject)));
    }
}
