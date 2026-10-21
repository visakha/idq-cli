package com.idq.cli.source.wic.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.EtlPatterns;
import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.PartyPattern.Check;
import com.idq.cli.core.PartyPattern.RaceSource;
import com.idq.cli.core.PartyPattern;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.reference.LookupRows;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.WicTargets;
import com.idq.cli.mdmdc.etldb.repo.WicPartyRepository;
import com.idq.cli.mdmdc.etldb.repo.WicPartyRoleRepository;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientDemographics;
import com.idq.cli.source.wic.etldb.models.WicSources;
import com.idq.cli.source.wic.etldb.repo.WicEtlSrcViewRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveStatusRepository;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_WIC_Pty` - client and family demographics plus member role. See [docs/mappings/030_m_Tgt_C_S_WIC_Pty.md].
@Service
public class WicPartyService {

    public static final MappingInfo INFO = MappingInfo.of("030", "m_Tgt_C_S_WIC_Pty", SourceSystem.WIC,
            List.of(WicTargets.Party.class, WicTargets.PartyRole.class), List.of(WicSources.EtlSrc.class,
            WicSources.InactiveStatus.class));

    /// Gender, ethnicity and race exceptions only for `CLIENT` rows; language for all rows.
    static final PartyPattern.Spec SPEC = new PartyPattern.Spec("WIC", RaceSource.INDICATORS, true, false,
            Set.of(Check.GENDER, Check.ETHNICITY, Check.RACE));

    private final WicEtlSrcViewRepository etlSrc;
    private final WicInactiveStatusRepository inactiveStatuses;
    private final WicPartyRepository parties;
    private final WicPartyRoleRepository partyRoles;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public WicPartyService(WicEtlSrcViewRepository etlSrc, WicInactiveStatusRepository inactiveStatuses,
            WicPartyRepository parties, WicPartyRoleRepository partyRoles, BadRecordRepository badRecords,
            EtlSettings settings) {
        this.etlSrc = etlSrc;
        this.inactiveStatuses = inactiveStatuses;
        this.parties = parties;
        this.partyRoles = partyRoles;
        this.badRecords = badRecords;
        this.settings = settings;
    }

    /// The `IdqMapInitQuery`.
    public List<ClientDemographics> fetchClientDemographics() {
        return etlSrc.fetchClientDemographics();
    }

    /// Parties deactivated by the validation mapping; their rows are not loaded.
    public InactiveStatus.Lookup fetchDeactivatedParties() {
        return new InactiveStatus.Lookup(LookupRows.toMap(inactiveStatuses.fetchInactiveStatuses()));
    }

    /// Only the ounces are converted (`BIRTH_WT_OZ * 28.35`; the pound term is commented out in IDQ).
    public static BigDecimal birthWeightGrams(BigDecimal ounces) {
        return ounces == null ? null : ounces.multiply(new BigDecimal("28.35"));
    }

    public MappingOutput transform(List<ClientDemographics> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var parties = new ArrayList<WicTargets.Party>();
        var roles = new ArrayList<WicTargets.PartyRole>();
        var bad = new ArrayList<BadRecord>();
        for (var r : Rows.where(rows, r -> inactive.isActive(r.ptySrcKey()))) {
            var key = trim(r.ptySrcKey());
            var v = PartyPattern.apply(SPEC, new PartyPattern.Input(key, r.id(), "CLIENT".equals(r.sourceTable()),
                    r.firstName(), r.middleName(), r.lastName(), null, r.dob(), r.gender(), r.ethnicity(),
                    r.languageCd(), null, r.raceWhiteInd(), r.raceAaInd(), r.raceAsianInd(), r.racePiInd(),
                    r.raceAnInd(), r.datekey()), ctx);
            bad.addAll(v.exceptions());
            var audit = MdmAudit.srcRowid(key).periodStart(r.datekey()).lastUpdated(ctx.runStart())
                    .created(r.datekey()).hubState(1).sourceUpdated(r.datekey());
            parties.add(new WicTargets.Party(key, audit, new Columns.Party("Indv", v.name().prefix(),
                    v.name().first(), v.name().middle(), v.name().last(), null, v.name().full(), v.gender().value(),
                    r.dob(), null, v.name().srcFull(), v.ethnicity().value(), r.ethnicity(), v.mdmRaceCd(),
                    v.srcRaceCd()), birthWeightGrams(r.birthWtOz()), v.language().value(), r.languageCd()));
            var roleKey = memberRole(key);
            roles.add(new WicTargets.PartyRole(roleKey, audit.withSrcRowid(roleKey),
                    new Columns.PartyRole(key, EtlPatterns.MEMBER)));
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(WicTargets.Party.class,
                        Rows.lastPerKey(parties, WicTargets.Party::pkeySrcObject)))
                .load(TargetBatch.replaceAll(WicTargets.PartyRole.class,
                        Rows.lastPerKey(roles, WicTargets.PartyRole::pkeySrcObject)))
                .reject(bad);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(WicPartyRepository.TABLE, replaceParties(output.rows(WicTargets.Party.class)));
        loaded.put(WicPartyRoleRepository.TABLE, replacePartyRoles(output.rows(WicTargets.PartyRole.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceParties(List<WicTargets.Party> rows) {
        settings.requireClearable(WicPartyRepository.TABLE);
        parties.deleteAll();
        return parties.insertAll(rows).size();
    }

    int replacePartyRoles(List<WicTargets.PartyRole> rows) {
        settings.requireClearable(WicPartyRoleRepository.TABLE);
        partyRoles.deleteAll();
        return partyRoles.insertAll(rows).size();
    }
}
