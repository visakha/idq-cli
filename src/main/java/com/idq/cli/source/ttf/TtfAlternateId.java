package com.idq.cli.source.ttf;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.ttf.TtfQueries.ClientIdentifier;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` - the TTF party source key as alternate id `024`.
/// See [docs/mappings/027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md].
@Component
public class TtfAlternateId extends SourceMapping<ClientIdentifier, InactiveStatus.Lookup>
        implements MemberMapping.AlternateId<ClientIdentifier, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("027", "m_Tgt_C_S_TTF_Pty_Rle_Alt_Id", SourceSystem.TTF,
            List.of("C_S_TTF_PTY_RLE_ALT_ID"), List.of("V_TTF_ETL_SRC", "STG_TTF_PTY_INACTIVE_STS"));

    public static final String ALT_ID_TYPE = "024";

    public TtfAlternateId(TtfQueries queries) {
        super(INFO, queries::fetchClientIdentifiers,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    /// `<party key>|Member|024|<party key>`
    public static String pkey(String partyKey) {
        return pipe(memberRole(partyKey), ALT_ID_TYPE, partyKey);
    }

    @Override
    public MappingOutput transform(List<ClientIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = Rows.where(rows, r -> inactive.isActive(r.ptySrcKey())).stream().map(r -> {
            var key = pkey(r.ptySrcKey());
            var audit = MdmAudit.srcRowid(key).periodStart(ctx.runStart()).lastUpdated(ctx.runStart())
                    .created(r.submitdate()).hubState(1).sourceUpdated(r.submitdate());
            return new TtfTargets.AlternateId(key, audit, new Columns.AlternateId(memberRole(r.ptySrcKey()),
                    ALT_ID_TYPE, r.ptySrcKey(), "Issued", ALT_ID_TYPE, null));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(TtfTargets.AlternateId.class,
                Rows.lastPerKey(ids, TtfTargets.AlternateId::pkeySrcObject)));
    }
}
