package com.idq.cli.source.fss.etlmap.svc;

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
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientDemographics;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.models.FssTargets;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import com.idq.cli.source.fss.etldb.repo.FssPartyRepository;
import com.idq.cli.source.fss.etldb.repo.FssPartyRoleRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_FSS_Pty` - client demographics and member role. See [docs/mappings/020_m_Tgt_C_S_FSS_Pty.md].
@Service
public class FssPartyService {

    public static final MappingInfo INFO = MappingInfo.of("020", "m_Tgt_C_S_FSS_Pty", SourceSystem.FSS,
            List.of("C_S_FSS_PTY", "C_S_FSS_PTY_RLE"), List.of(FssSources.EtlSrc.class,
            FssTargets.InactiveStatus.class));

    /// Gender, ethnicity and race exceptions only for `CLIENT` rows; language and suffix for all rows.
    static final PartyPattern.Spec SPEC = new PartyPattern.Spec("FSS", RaceSource.INDICATORS, true, true,
            Set.of(Check.GENDER, Check.ETHNICITY, Check.RACE));

    private final FssEtlSrcViewRepository etlSrc;
    private final FssInactiveStatusRepository inactiveStatuses;
    private final FssPartyRepository parties;
    private final FssPartyRoleRepository partyRoles;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public FssPartyService(FssEtlSrcViewRepository etlSrc, FssInactiveStatusRepository inactiveStatuses,
            FssPartyRepository parties, FssPartyRoleRepository partyRoles, BadRecordRepository badRecords,
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

    public MappingOutput transform(List<ClientDemographics> rows, InactiveStatus.Lookup inactive, EtlContext ctx) {
        var parties = new ArrayList<FssTargets.Party>();
        var roles = new ArrayList<FssTargets.PartyRole>();
        var bad = new ArrayList<BadRecord>();
        for (var r : Rows.where(rows, r -> inactive.isActive(r.ptySrcKey()))) {
            var key = trim(r.ptySrcKey());
            var v = PartyPattern.apply(SPEC, new PartyPattern.Input(key, r.idClient(), "CLIENT".equals(r.sourceType()),
                    r.nmFirst(), r.nmMiddle(), r.nmLast(), r.cdSuffix(), r.dtDob(), r.cdGender(), r.cdHispanic(),
                    r.languageCd(), null, r.raceWhite(), r.raceAa(), r.raceAsian(), r.racePi(), r.raceAn(),
                    r.dtLastUpdate()), ctx);
            bad.addAll(v.exceptions());
            var audit = MdmAudit.srcRowid(key).periodStart(r.dtLastUpdate()).lastUpdated(ctx.runStart())
                    .created(r.dtLastUpdate()).hubState(1).sourceUpdated(r.dtLastUpdate());
            parties.add(new FssTargets.Party(key, audit, new Columns.Party("Indv", v.name().prefix(), v.name().first(),
                    v.name().middle(), v.name().last(), v.suffix().value(), v.name().full(), v.gender().value(),
                    r.dtDob(), null, v.name().srcFull(), v.ethnicity().value(), r.cdHispanic(), v.mdmRaceCd(),
                    v.srcRaceCd()), v.language().value()));
            var roleKey = memberRole(key);
            roles.add(new FssTargets.PartyRole(roleKey, audit.withSrcRowid(roleKey),
                    new Columns.PartyRole(key, EtlPatterns.MEMBER)));
        }
        return MappingOutput.empty()
                .load(TargetBatch.replaceAll(FssTargets.Party.class,
                        Rows.lastPerKey(parties, FssTargets.Party::pkeySrcObject)))
                .load(TargetBatch.replaceAll(FssTargets.PartyRole.class,
                        Rows.lastPerKey(roles, FssTargets.PartyRole::pkeySrcObject)))
                .reject(bad);
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(FssPartyRepository.TABLE, replaceParties(output.rows(FssTargets.Party.class)));
        loaded.put(FssPartyRoleRepository.TABLE, replacePartyRoles(output.rows(FssTargets.PartyRole.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int replaceParties(List<FssTargets.Party> rows) {
        settings.requireClearable(FssPartyRepository.TABLE);
        parties.deleteAll();
        return parties.insertAll(rows).size();
    }

    int replacePartyRoles(List<FssTargets.PartyRole> rows) {
        settings.requireClearable(FssPartyRoleRepository.TABLE);
        partyRoles.deleteAll();
        return partyRoles.insertAll(rows).size();
    }
}
