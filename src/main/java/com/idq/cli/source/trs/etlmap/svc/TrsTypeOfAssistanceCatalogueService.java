package com.idq.cli.source.trs.etlmap.svc;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.ReferenceData.CodeValue;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;
import com.idq.cli.mdmdc.etldb.repo.TrsTypeOfAssistanceCatalogueRepository;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceType;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsLuToaDeltaRepository;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Stg_TOA` - the TIERS type-of-assistance catalogue (workflow `wf_TRS_Stage_Load_TOA`, run after
/// `wf_TRS_Stage_Load_1_Ongoing`). See [docs/mappings/035_m_Tgt_C_S_TRS_Stg_TOA.md].
@Service
public class TrsTypeOfAssistanceCatalogueService {

    public static final MappingInfo INFO = MappingInfo.of("035", "m_Tgt_C_S_TRS_Stg_TOA", SourceSystem.TRS,
            List.of(TrsTargets.TypeOfAssistanceCatalogue.class), List.of(TrsSources.LuToaDelta.class));

    /// The key passes a string(10) port of `Exp_TOA_Load`, the program code a string(9) port.
    static final int KEY_PRECISION = 10;
    static final int PROGRAM_PRECISION = 9;

    /// Latest TIERS change first (IDQ keeps the first row read, in no defined order; see the mapping document).
    static final Comparator<AssistanceType> LATEST_FIRST =
            Comparator.comparing(AssistanceType::updateDt, Comparator.nullsLast(Comparator.reverseOrder()))
                    .thenComparing(AssistanceType::uniqueTransId, Comparator.nullsLast(Comparator.reverseOrder()));

    private final TrsLuToaDeltaRepository luToaDelta;
    private final TrsTypeOfAssistanceCatalogueRepository catalogue;

    public TrsTypeOfAssistanceCatalogueService(TrsLuToaDeltaRepository luToaDelta,
            TrsTypeOfAssistanceCatalogueRepository catalogue) {
        this.luToaDelta = luToaDelta;
        this.catalogue = catalogue;
    }

    /// The `IdqMapInitQuery`.
    public List<AssistanceType> fetchAssistanceTypes() {
        return luToaDelta.fetchAssistanceTypes();
    }

    /// `<TOA master code>`: `LOOKUP_CODE_VALUE` (`TOA`) matched on the label, cut to the port precision.
    public static String pkey(String toaMasterCode) {
        return Infa.substr(toaMasterCode, 1, KEY_PRECISION);
    }

    /// One catalogue row per TOA master code. A code without a TOA label has no key: IDQ gets it rejected by Oracle
    /// (`PKEY_SRC_OBJECT NOT NULL`) and logs nothing, so it is dropped here. A key that repeats (the code under
    /// several programs or history rows) is rejected by the unique index after the first row: the latest is kept.
    public MappingOutput transform(List<AssistanceType> rows, NoLookups lookups, EtlContext ctx) {
        var loaded = new ArrayList<TrsTargets.TypeOfAssistanceCatalogue>();
        for (var r : Rows.sorted(rows, LATEST_FIRST)) {
            var toa = ctx.reference().codeValueByLabel("TOA", r.toaCode()).orElse(null);
            var key = toa == null ? null : pkey(toa.mstrRefCode());
            if (key == null) {
                continue;
            }
            var program = ctx.reference().codeValueByLabel("MEMBER_PRG", r.programCode())
                    .map(CodeValue::mstrRefCode).map(code -> Infa.substr(code, 1, PROGRAM_PRECISION)).orElse(null);
            loaded.add(new TrsTargets.TypeOfAssistanceCatalogue(key, ctx.runStart(), r.createDt(), "admin",
                    Infa.substr(r.updateUserId(), 1, 50), Infa.substr(key, 1, MdmAudit.SRC_ROWID_PRECISION), 1, key,
                    Infa.substr(toa.mstrRefLabel(), 1, 100), Infa.substr(r.toaDesc(), 1, 250), program,
                    r.effBeginDt(), r.effEndDt()));
        }
        return MappingOutput.empty().load(TargetBatch.append(TrsTargets.TypeOfAssistanceCatalogue.class,
                Rows.firstPerKey(loaded, TrsTargets.TypeOfAssistanceCatalogue::pkeySrcObject)));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsTypeOfAssistanceCatalogueRepository.TABLE,
                catalogue.insertAll(output.rows(TrsTargets.TypeOfAssistanceCatalogue.class)).size());
        return loaded;
    }
}
