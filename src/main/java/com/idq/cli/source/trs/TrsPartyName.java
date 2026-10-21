package com.idq.cli.source.trs;

import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.MemberAlias;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Pty_Nm` - member aliases. See [docs/mappings/003_m_Tgt_C_S_TRS_Pty_Nm.md].
@Component
public class TrsPartyName extends SourceMapping<MemberAlias, NoLookups>
        implements MemberMapping.AlternateName<MemberAlias, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("003", "m_Tgt_C_S_TRS_Pty_Nm", SourceSystem.TRS,
            List.of("C_S_TRS_PTY_NM"), List.of(TrsSources.CvDcMciAliasDelta.class, TrsSources.DcAliasDelta.class,
            TrsTargets.ValidMember.class));

    /// IDQ parameter `$MemberNameTypeCode` (label `Alias`).
    public static final String ALIAS_NAME_TYPE = "002";

    public TrsPartyName(TrsQueries queries) {
        super(INFO, queries::fetchMemberAliases, NoLookups::none);
    }

    /// `<party key>|002|<alias sequence>`
    public static String pkey(String partyKey, Long sequenceNum) {
        return pipe(partyKey, ALIAS_NAME_TYPE, Infa.toChar(sequenceNum));
    }

    /// Aliases need a first and a last name; trailing digits are removed before the regular name standardization.
    @Override
    public MappingOutput transform(List<MemberAlias> rows, NoLookups lookups, EtlContext ctx) {
        var names = Rows.where(rows, r -> r.firstName() != null && r.lastName() != null).stream().map(r -> {
            var srcFull = Infa.fullName(r.firstName(), r.midName(), r.lastName());
            var trailing = NameStandardization.removeTrailingNumbers(r.firstName(), r.midName(), r.lastName(),
                    srcFull);
            var std = NameStandardization.standardize(new NameStandardization.Input(trailing.first(),
                    trailing.middle(), trailing.last(), srcFull, r.prefixName(), r.sufxName(), "TRS"), ctx);
            var key = pkey(r.pkeyPty(), r.sequenceNum());
            var audit = MdmAudit.srcRowid(key).periodStart(r.createDt()).lastUpdated(ctx.runStart())
                    .created(r.createDt()).sourceUpdated(r.createDt());
            return new TrsTargets.PartyName(key, audit, new Columns.PartyName(r.pkeyPty(), ALIAS_NAME_TYPE,
                    std.first(), std.middle(), std.last(), std.prefix(), std.full(), std.suffix(), srcFull));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(TrsTargets.PartyName.class,
                Rows.lastPerKey(Rows.distinct(names), TrsTargets.PartyName::pkeySrcObject)));
    }
}
