package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.ReferenceData.CodeValue;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;
import com.idq.cli.mdmdc.etldb.repo.TrsTypeOfAssistanceRepository;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceSegment;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsCvMciEdgIndvToaDeltaRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Pty_Rle_TOA` - type of assistance per eligibility segment.
/// See [docs/mappings/008_m_Tgt_C_S_TRS_Pty_Rle_TOA.md].
@Service
public class TrsTypeOfAssistanceService {

    public static final MappingInfo INFO = MappingInfo.of("008", "m_Tgt_C_S_TRS_Pty_Rle_TOA", SourceSystem.TRS,
            List.of(TrsTargets.TypeOfAssistance.class), List.of(TrsSources.CvMciEdgIndvToaDelta.class,
            TrsSources.ValidMember.class));

    private final TrsCvMciEdgIndvToaDeltaRepository cvMciEdgIndvToaDelta;
    private final TrsTypeOfAssistanceRepository typesOfAssistance;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsTypeOfAssistanceService(TrsCvMciEdgIndvToaDeltaRepository cvMciEdgIndvToaDelta,
            TrsTypeOfAssistanceRepository typesOfAssistance, BadRecordRepository badRecords, EtlSettings settings) {
        this.cvMciEdgIndvToaDelta = cvMciEdgIndvToaDelta;
        this.typesOfAssistance = typesOfAssistance;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<AssistanceSegment> fetchAssistanceSegments() {
        return cvMciEdgIndvToaDelta.fetchAssistanceSegments();
    }

    /// `EDG_NUM|PROGRAM_CD|MCI_CREATE_SEQ`
    public static String segmentKey(AssistanceSegment r) {
        return pipe(r.edgNum(), r.programCd(), r.mciCreateSeq());
    }

    /// `DADS` for `LTSS_ELIG_PER`, `TIERS` for `MCI_EDG_INDV`.
    public static String toaSource(String srcTbl) {
        return switch (srcTbl == null ? "" : srcTbl) {
            case "LTSS_ELIG_PER" -> "DADS";
            case "MCI_EDG_INDV" -> "TIERS";
            default -> null;
        };
    }

    /// `<indv id>|Member|<MDM TOA code>|<TOA source>|<segment key>`
    public static String pkey(AssistanceSegment r, String toaMasterCode) {
        return pipe(memberRole(r.indvId()), toaMasterCode, toaSource(r.srcTbl()), segmentKey(r));
    }

    /// Segments whose TOA does not translate (`LOOKUP_CODE_VALUE`, `TOA`) or that start after they end go to the
    /// exception queue; all others are loaded.
    public MappingOutput transform(List<AssistanceSegment> rows, NoLookups lookups, EtlContext ctx) {
        var segments = new ArrayList<TrsTargets.TypeOfAssistance>();
        var bad = new ArrayList<BadRecord>();
        for (var r : rows) {
            var toa = ctx.reference().codeValue("TOA", "TRS", r.typeOfAssistanceCd()).map(CodeValue::mstrRefCode)
                    .orElse(null);
            var key = pkey(r, toa);
            var roleKey = memberRole(r.indvId());
            boolean badValue = toa == null;
            boolean backwards = r.beginDt() != null && r.endDt() != null && r.beginDt().isAfter(r.endDt());
            if (badValue) {
                bad.add(ctx.badRecord().ids(r.indvId(), r.edgNum(), r.mciCreateSeq())
                        .exception(ctx.exception("Invalid_TOA"))
                        .attribute("Type of Assistance", r.typeOfAssistanceCd()).period(r.beginDt(), r.endDt())
                        .build());
            }
            if (backwards) {
                bad.add(ctx.badRecord().ids(key, roleKey, null)
                        .exception(ctx.exception("Period_Start_Date_>_Period_End_Date"))
                        .attribute("Effective Date", null).period(r.beginDt(), r.endDt()).build());
            }
            if (!badValue && !backwards) {
                var audit = MdmAudit.srcRowid(key).period(r.beginDt(), r.endDt()).lastUpdated(ctx.runStart())
                        .created(r.createDt()).sourceUpdated(r.createDt());
                segments.add(new TrsTargets.TypeOfAssistance(key, audit, new Columns.TypeOfAssistance(
                        toaSource(r.srcTbl()), toa, r.beginDt(), r.endDt(), roleKey, r.partStatusCd(), r.ptyPk(),
                        Infa.toChar(r.caseNum()), Infa.toChar(r.edgNum()), segmentKey(r), r.systemCd(),
                        r.convertDt())));
            }
        }
        return MappingOutput.empty().load(TargetBatch.replaceAll(TrsTargets.TypeOfAssistance.class, segments))
                .reject(bad);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsTypeOfAssistanceRepository.TABLE,
                replaceTypesOfAssistance(output.rows(TrsTargets.TypeOfAssistance.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceTypesOfAssistance(List<TrsTargets.TypeOfAssistance> rows) {
        settings.requireClearable(TrsTypeOfAssistanceRepository.TABLE);
        typesOfAssistance.deleteAll();
        return typesOfAssistance.insertAll(rows).size();
    }
}
