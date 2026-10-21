package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
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
import com.idq.cli.mdmdc.etldb.repo.TrsPlanRepository;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.ManagedCarePlan;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsInManagedCareDeltaRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Pty_Rle_Pln` - managed care plan of a member. See [docs/mappings/005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md].
@Service
public class TrsPlanService {

    public static final MappingInfo INFO = MappingInfo.of("005", "m_Tgt_C_S_TRS_Pty_Rle_Pln", SourceSystem.TRS,
            List.of(TrsTargets.Plan.class), List.of(TrsSources.InManagedCareDelta.class, TrsSources.ValidMember.class));

    private final TrsInManagedCareDeltaRepository inManagedCareDelta;
    private final TrsPlanRepository plans;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsPlanService(TrsInManagedCareDeltaRepository inManagedCareDelta, TrsPlanRepository plans,
            BadRecordRepository badRecords, EtlSettings settings) {
        this.inManagedCareDelta = inManagedCareDelta;
        this.plans = plans;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<ManagedCarePlan> fetchManagedCarePlans() {
        return inManagedCareDelta.fetchManagedCarePlans();
    }

    /// `<indv id>|Member|<MDM plan code>`
    public static String pkey(Long indvId, String planMasterCode) {
        return pipe(Infa.toChar(indvId), "Member", planMasterCode);
    }

    /// Plans translate through `V_LOOKUP_CODE_VALUE` (`PLAN_CD`, source `MAX`). Untranslatable plans produce one
    /// `Invalid_Plan` exception per individual (the first in source order).
    public MappingOutput transform(List<ManagedCarePlan> rows, NoLookups lookups, EtlContext ctx) {
        var plans = rows.stream().filter(r -> master(r, ctx) != null).map(r -> {
            var key = pkey(r.indvId(), master(r, ctx));
            var audit = MdmAudit.srcRowid(key).period(r.beginDt(), r.endDt()).lastUpdated(ctx.runStart())
                    .created(ctx.runStart()).sourceUpdated(r.createDt());
            return new TrsTargets.Plan(key, audit, new Columns.Plan(memberRole(Infa.toChar(r.indvId())),
                    master(r, ctx)));
        }).toList();
        var bad = Rows.firstPerKey(Rows.where(rows, r -> master(r, ctx) == null), ManagedCarePlan::indvId).stream()
                .map(r -> ctx.badRecord().ids(r.indvId(), Infa.toChar(r.beginDt(), "yyyy-MM-dd"), null)
                        .exception(ctx.exception("Invalid_Plan")).attribute("Plan", r.mcPlan())
                        .period(r.beginDt(), null).build())
                .toList();
        var ordered = Rows.sorted(plans, Rows.<TrsTargets.Plan, String>asc(TrsTargets.Plan::pkeySrcObject)
                .thenComparing(Rows.asc(p -> p.audit().periodStartDate()))
                .thenComparing(Rows.asc(p -> p.audit().periodEndDate())));
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(TrsTargets.Plan.class,
                        Rows.lastPerKey(ordered, TrsTargets.Plan::pkeySrcObject)))
                .reject(bad);
    }

    private static String master(ManagedCarePlan r, EtlContext ctx) {
        return ctx.reference().masterCode("PLAN_CD", "MAX", r.mcPlan()).orElse(null);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsPlanRepository.TABLE, replacePlans(output.rows(TrsTargets.Plan.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replacePlans(List<TrsTargets.Plan> rows) {
        settings.requireClearable(TrsPlanRepository.TABLE);
        plans.deleteAll();
        return plans.insertAll(rows).size();
    }
}
