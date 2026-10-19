package com.idq.cli.source.wic;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.lpad;
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
import com.idq.cli.source.wic.WicQueries.ClientIdentifier;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` - WIC client id (`020`) or family id (`021`).
/// See [docs/mappings/032_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md].
@Component
public class WicAlternateId extends SourceMapping<ClientIdentifier, InactiveStatus.Lookup>
        implements MemberMapping.AlternateId<ClientIdentifier, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("032", "m_Tgt_C_S_WIC_Pty_Rle_Alt_Id", SourceSystem.WIC,
            List.of("C_S_WIC_PTY_RLE_ALT_ID"), List.of("V_WIC_ETL_SRC", "STG_WIC_PTY_INACTIVE_STS"));

    public WicAlternateId(WicQueries queries) {
        super(INFO, queries::fetchClientIdentifiers,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    public static String altIdType(String sourceTable) {
        return "CLIENT".equals(sourceTable) ? "020" : "021";
    }

    /// `<party key>|Member|<020 or 021>|<id, 12 digits>`
    public static String pkey(ClientIdentifier r) {
        return pipe(memberRole(r.ptySrcKey()), altIdType(r.sourceTable()), lpad(r.id(), 12, '0'));
    }

    @Override
    public MappingOutput transform(List<ClientIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = Rows.where(rows, r -> inactive.isActive(r.ptySrcKey())).stream().map(r -> {
            var type = altIdType(r.sourceTable());
            var audit = MdmAudit.srcRowid(pipe(r.id(), type)).periodStart(r.datekey()).lastUpdated(ctx.runStart())
                    .created(r.datekey()).sourceUpdated(r.datekey());
            return new WicTargets.AlternateId(pkey(r), audit, new Columns.AlternateId(memberRole(r.ptySrcKey()), type,
                    lpad(r.id(), 12, '0'), "Issued", type, null));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(WicTargets.AlternateId.class,
                Rows.lastPerKey(ids, WicTargets.AlternateId::pkeySrcObject)));
    }
}
