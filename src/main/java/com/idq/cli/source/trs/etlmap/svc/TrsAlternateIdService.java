package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.lpad;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.reference.ReferenceData.CodeValue;
import com.idq.cli.core.rules.IdentifierRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberIdentifiers;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.models.TrsTargets;
import com.idq.cli.source.trs.etldb.repo.TrsAlternateIdRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcIndvDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcIndvHistRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` with `mplt_TRS_Pty_Rle_Alt_Id_Normalization` - Medicaid id, SSN and member id.
/// See [docs/mappings/004_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md].
@Service
public class TrsAlternateIdService {

    public static final MappingInfo INFO = MappingInfo.of("004", "m_Tgt_C_S_TRS_Pty_Rle_Alt_Id", SourceSystem.TRS,
            List.of("C_S_TRS_PTY_RLE_ALT_ID"), List.of(TrsSources.CvDcMciIndvDelta.class, TrsSources.DcIndvDelta.class,
            TrsSources.CvDcMrgSprtIndvDelta.class, TrsTargets.ValidMember.class, TrsSources.DcIndvHist.class));

    public static final String MEDICAID_ID = "002";
    public static final String SSN = "004";
    public static final String MEMBER_ID = "007";

    /// @param validSsns `<indv id>|<ssn>` pairs validated by SSA (`lkp_Valid_SSN`)
    public record Lookups(Set<String> validSsns) {
        public boolean isValid(String memberId, Long ssn) {
            return ssn != null && validSsns.contains(memberId + "|" + ssn);
        }
    }

    private final TrsDcIndvDeltaRepository dcIndvDelta;
    private final TrsDcIndvHistRepository dcIndvHist;
    private final TrsAlternateIdRepository alternateIds;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsAlternateIdService(TrsDcIndvDeltaRepository dcIndvDelta, TrsDcIndvHistRepository dcIndvHist,
            TrsAlternateIdRepository alternateIds, BadRecordRepository badRecords, EtlSettings settings) {
        this.dcIndvDelta = dcIndvDelta;
        this.dcIndvHist = dcIndvHist;
        this.alternateIds = alternateIds;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<MemberIdentifiers> fetchMemberIdentifiers() {
        return dcIndvDelta.fetchMemberIdentifiers();
    }

    /// SSNs validated by the SSA (`STG_TRS_H_DC_INDV`).
    public Lookups fetchValidSsns() {
        return new Lookups(dcIndvHist.fetchValidSsns().stream()
                .map(v -> v.indvId() + "|" + v.ssn()).collect(Collectors.toSet()));
    }

    /// `<party key>|Member|<alternate id type>|<value>`
    public static String pkey(String partyKey, String altIdType, String value) {
        return pipe(partyKey, "Member", altIdType, value);
    }

    /// One normalized identifier occurrence (`NRM_ALT_ID`).
    record Candidate(MemberIdentifiers src, String type, String value, ExceptionInfo exception) {}

    public MappingOutput transform(List<MemberIdentifiers> rows, Lookups lookups, EtlContext ctx) {
        var valid = new ArrayList<TrsTargets.AlternateId>();
        var bad = new ArrayList<BadRecord>();
        rows.stream().flatMap(r -> normalize(r, lookups, ctx))
                .filter(c -> Infa.hasText(c.value()))
                .forEach(c -> {
                    var label = ctx.reference().codeValueByMaster("ALT_ID_TP", "TRS", c.type());
                    if (c.exception().present()) {
                        bad.add(ctx.badRecord().ids(c.src().ptyPkey(), null, null).exception(c.exception())
                                .exceptionType("Bad Value")
                                .attribute(label.map(CodeValue::mstrRefLabel).orElse(null), c.value()).build());
                    } else {
                        var type = label.map(CodeValue::mstrRefCode).orElse(null);
                        var key = pkey(c.src().ptyPkey(), type, c.value());
                        var audit = MdmAudit.srcRowid(key).periodStart(c.src().startDt()).lastUpdated(ctx.runStart())
                                .created(c.src().startDt()).sourceUpdated(c.src().startDt());
                        valid.add(new TrsTargets.AlternateId(key, audit, new Columns.AlternateId(
                                memberRole(c.src().ptyPkey()), type, c.value(), "Issued", type, c.src().cvInd())));
                    }
                });
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(TrsTargets.AlternateId.class,
                        Rows.lastPerKey(valid, TrsTargets.AlternateId::pkeySrcObject)))
                .reject(bad);
    }

    /// The Medicaid id and the member id are both the TIERS individual id; the SSN only counts when SSA validated
    /// it and passes the SSN rule (an invalid SSN is blanked and therefore dropped).
    static Stream<Candidate> normalize(MemberIdentifiers r, Lookups lookups, EtlContext ctx) {
        var ssn = lookups.isValid(r.memberId(), r.ssn()) ? lpad(r.ssn(), 9, '0') : null;
        var checkedSsn = IdentifierRules.ssn(ssn, ctx);
        return Stream.of(
                new Candidate(r, MEDICAID_ID, r.memberId(), IdentifierRules.medicaidId(r.memberId(), ctx).exception()),
                new Candidate(r, SSN, checkedSsn.value(), checkedSsn.exception()),
                new Candidate(r, MEMBER_ID, r.memberId(), IdentifierRules.memberId(r.memberId(), ctx).exception()));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsAlternateIdRepository.TABLE, replaceAlternateIds(output.rows(TrsTargets.AlternateId.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceAlternateIds(List<TrsTargets.AlternateId> rows) {
        settings.requireClearable(TrsAlternateIdRepository.TABLE);
        alternateIds.deleteAll();
        return alternateIds.insertAll(rows).size();
    }
}
