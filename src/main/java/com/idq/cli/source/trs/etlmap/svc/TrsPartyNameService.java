package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;
import com.idq.cli.mdmdc.etldb.repo.TrsPartyNameRepository;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberAlias;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsDcAliasDeltaRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Pty_Nm` - member aliases. See [docs/mappings/003_m_Tgt_C_S_TRS_Pty_Nm.md].
@Service
public class TrsPartyNameService {

    public static final MappingInfo INFO = MappingInfo.of("003", "m_Tgt_C_S_TRS_Pty_Nm", SourceSystem.TRS,
            List.of(TrsTargets.PartyName.class), List.of(TrsSources.CvDcMciAliasDelta.class,
            TrsSources.DcAliasDelta.class, TrsSources.ValidMember.class));

    /// IDQ parameter `$MemberNameTypeCode` (label `Alias`).
    public static final String ALIAS_NAME_TYPE = "002";

    private final TrsDcAliasDeltaRepository dcAliasDelta;
    private final TrsPartyNameRepository partyNames;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsPartyNameService(TrsDcAliasDeltaRepository dcAliasDelta, TrsPartyNameRepository partyNames,
            BadRecordRepository badRecords, EtlSettings settings) {
        this.dcAliasDelta = dcAliasDelta;
        this.partyNames = partyNames;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<MemberAlias> fetchMemberAliases() {
        return dcAliasDelta.fetchMemberAliases();
    }

    /// `<party key>|002|<alias sequence>`
    public static String pkey(String partyKey, Long sequenceNum) {
        return pipe(partyKey, ALIAS_NAME_TYPE, Infa.toChar(sequenceNum));
    }

    /// Aliases need a first and a last name; trailing digits are removed before the regular name standardization.
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
        return MappingOutput.empty().load(TargetBatch.append(TrsTargets.PartyName.class,
                Rows.lastPerKey(Rows.distinct(names), TrsTargets.PartyName::pkeySrcObject)));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsPartyNameRepository.TABLE, insertPartyNames(output.rows(TrsTargets.PartyName.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int insertPartyNames(List<TrsTargets.PartyName> rows) {
        return partyNames.insertAll(rows).size();
    }
}
