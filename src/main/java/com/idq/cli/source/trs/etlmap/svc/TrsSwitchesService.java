package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;
import com.idq.cli.mdmdc.etldb.repo.TrsManagedAttributeRepository;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberSwitches;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsDcIndvDeltaRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` - TIERS switches as managed attributes.
/// See [docs/mappings/007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md].
@Service
public class TrsSwitchesService {

    public static final MappingInfo INFO = MappingInfo.of("007", "m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw", SourceSystem.TRS,
            List.of(TrsTargets.ManagedAttribute.class), List.of(TrsSources.DcIndvDelta.class,
            TrsSources.CvDcMciIndvDelta.class, TrsSources.ValidMember.class));

    private final TrsDcIndvDeltaRepository dcIndvDelta;
    private final TrsManagedAttributeRepository managedAttributes;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsSwitchesService(TrsDcIndvDeltaRepository dcIndvDelta, TrsManagedAttributeRepository managedAttributes,
            BadRecordRepository badRecords, EtlSettings settings) {
        this.dcIndvDelta = dcIndvDelta;
        this.managedAttributes = managedAttributes;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<MemberSwitches> fetchMemberSwitches() {
        return dcIndvDelta.fetchMemberSwitches();
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

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsManagedAttributeRepository.TABLE,
                replaceManagedAttributes(output.rows(TrsTargets.ManagedAttribute.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceManagedAttributes(List<TrsTargets.ManagedAttribute> rows) {
        settings.requireClearable(TrsManagedAttributeRepository.TABLE);
        managedAttributes.deleteAll();
        return managedAttributes.insertAll(rows).size();
    }
}
