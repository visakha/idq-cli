package com.idq.cli.source.trs;

import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.toChar;

import com.idq.cli.core.EtlContext;
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
import com.idq.cli.source.trs.TrsQueries.AuthorizedRepresentative;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing` - authorized representative flag of a member.
/// See [docs/mappings/002_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md].
@Component
public class TrsAuthorizedRepresentative extends SourceMapping<AuthorizedRepresentative, NoLookups>
        implements MemberMapping.ManagedAttribute<AuthorizedRepresentative, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("002", "m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing",
            SourceSystem.TRS, List.of("C_S_TRS_PTY_MNG_ATTR"), List.of(TrsSources.DDcPrimaryPayee.class,
            TrsSources.DcPrimaryPayee.class, TrsSources.CvEdMciEdgIndv.class, TrsSources.DCvEdMciEdgIndv.class,
            TrsSources.DcCases.class, TrsSources.DDcCases.class, TrsSources.DcCaseIndv.class,
            TrsTargets.ValidMember.class));

    /// IDQ parameter `$ATTR_TP_AUTH_REP`.
    public static final String ATTR_TP_AUTH_REP = "Auth_Rep_Flag";

    public TrsAuthorizedRepresentative(TrsQueries queries) {
        super(INFO, queries::fetchAuthorizedRepresentatives, NoLookups::none);
    }

    public static String pkey(Long indvId) {
        return pipe(indvId, ATTR_TP_AUTH_REP);
    }

    /// One flag per member; the latest eligibility segment supplies the dates and the period end is the greatest
    /// segment end (`agg_Dedup_TRS_Pty_Mng_Attr`). Only `Auth_Rep_Flag` rows are replaced (IDQ pre-SQL delete).
    @Override
    public MappingOutput transform(List<AuthorizedRepresentative> rows, NoLookups lookups, EtlContext ctx) {
        var ordered = Rows.sorted(rows, Rows.<AuthorizedRepresentative, Long>asc(AuthorizedRepresentative::indvId)
                .thenComparing(Rows.asc(AuthorizedRepresentative::effBeginDt)));
        var maxEnd = ordered.stream().filter(r -> r.effEndDt() != null).collect(Collectors.toMap(
                r -> pkey(r.indvId()), AuthorizedRepresentative::effEndDt, (a, b) -> a.isAfter(b) ? a : b));
        var flags = Rows.lastPerKey(ordered, r -> pkey(r.indvId())).stream().map(r -> {
            var key = pkey(r.indvId());
            var audit = MdmAudit.srcRowid(key).period(r.effBeginDt(), maxEnd.get(key)).lastUpdated(ctx.runStart())
                    .created(r.createDt()).sourceUpdated(r.createDt());
            return new TrsTargets.ManagedAttribute(key, audit,
                    new Columns.ManagedAttribute(toChar(r.indvId()), ATTR_TP_AUTH_REP, r.arFlag()));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceWhere(TrsTargets.ManagedAttribute.class, "MNG_ATTR_TP",
                ATTR_TP_AUTH_REP, flags));
    }
}
