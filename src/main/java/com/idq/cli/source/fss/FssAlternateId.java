package com.idq.cli.source.fss;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.Infa;
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
import com.idq.cli.source.fss.FssQueries.ClientIdentifier;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` - FSS client id (`022`) or registration id (`023`).
/// See [docs/mappings/022_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md].
@Component
public class FssAlternateId extends SourceMapping<ClientIdentifier, InactiveStatus.Lookup>
        implements MemberMapping.AlternateId<ClientIdentifier, InactiveStatus.Lookup> {

    public static final MappingInfo INFO = MappingInfo.of("022", "m_Tgt_C_S_FSS_Pty_Rle_Alt_Id", SourceSystem.FSS,
            List.of("C_S_FSS_PTY_RLE_ALT_ID"), List.of("V_FSS_ETL_SRC", "STG_FSS_PTY_INACTIVE_STS"));

    public FssAlternateId(FssQueries queries) {
        super(INFO, queries::fetchClientIdentifiers,
                () -> new InactiveStatus.Lookup(LookupRows.toMap(queries.fetchInactiveStatuses())));
    }

    public static String altIdType(String sourceType) {
        return "CLIENT".equals(sourceType) ? "022" : "023";
    }

    /// `<party key>|Member|<022 or 023>|<client id, 10 digits>`
    public static String pkey(ClientIdentifier r) {
        return pipe(memberRole(r.ptySrcKey()), altIdType(r.sourceType()), lpad(r.idClient(), 10, '0'));
    }

    @Override
    public MappingOutput transform(List<ClientIdentifier> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var ids = Rows.where(rows, r -> inactive.isActive(r.ptySrcKey())).stream().map(r -> {
            var type = altIdType(r.sourceType());
            var audit = MdmAudit.srcRowid(pipe(Infa.toChar(r.idClient()), type)).periodStart(r.dtCreated())
                    .lastUpdated(ctx.runStart()).created(r.dtCreated()).hubState(1).sourceUpdated(ctx.runStart());
            return new FssTargets.AlternateId(pkey(r), audit, new Columns.AlternateId(memberRole(r.ptySrcKey()), type,
                    lpad(r.idClient(), 10, '0'), "Issued", type, null));
        }).toList();
        return MappingOutput.empty().load(TargetBatch.replaceAll(FssTargets.AlternateId.class,
                Rows.lastPerKey(ids, FssTargets.AlternateId::pkeySrcObject)));
    }
}
