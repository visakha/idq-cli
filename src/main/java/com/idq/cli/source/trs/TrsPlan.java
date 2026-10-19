package com.idq.cli.source.trs;

import static com.idq.cli.core.EtlPatterns.memberRole;
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
import com.idq.cli.source.trs.TrsQueries.ManagedCarePlan;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Rle_Pln` - managed care plan of a member. See [docs/mappings/005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md].
@Component
public class TrsPlan extends SourceMapping<ManagedCarePlan, NoLookups>
        implements MemberMapping.Role<ManagedCarePlan, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("005", "m_Tgt_C_S_TRS_Pty_Rle_Pln", SourceSystem.TRS,
            List.of("C_S_TRS_PTY_RLE_PLN"), List.of("STG_TRS_D_IN_MANAGED_CARE", "STG_TRS_VALID_MEMBERS"));

    public TrsPlan(TrsQueries queries) {
        super(INFO, queries::fetchManagedCarePlans, NoLookups::none);
    }

    /// `<indv id>|Member|<MDM plan code>`
    public static String pkey(Long indvId, String planMasterCode) {
        return pipe(Infa.toChar(indvId), "Member", planMasterCode);
    }

    /// Plans translate through `V_LOOKUP_CODE_VALUE` (`PLAN_CD`, source `MAX`). Untranslatable plans produce one
    /// `Invalid_Plan` exception per individual (the first in source order).
    @Override
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
}
