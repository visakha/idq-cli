package com.idq.cli.source.cre.etlmap.svc;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.RUN;
import static com.idq.cli.Fixtures.reference;
import static com.idq.cli.Fixtures.stub;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.rules.PassThroughAddressValidator;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.mdmdc.etldb.models.CreTargets;
import com.idq.cli.mdmdc.etldb.repo.CreAddressRepository;
import com.idq.cli.mdmdc.etldb.repo.CreAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.CrePartyRepository;
import com.idq.cli.mdmdc.etldb.repo.CrePartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.CrePhoneRepository;
import com.idq.cli.source.cre.etldb.models.CreQueryRows.CareClient;
import com.idq.cli.source.cre.etldb.models.CreQueryRows.PartyXref;
import com.idq.cli.source.cre.etldb.models.CreSources;
import com.idq.cli.source.cre.etldb.repo.CreCareClientsDeltaRepository;
import com.idq.cli.source.cre.etldb.repo.CrePartyHmrgRepository;
import com.idq.cli.source.cre.etldb.repo.CrePartyXrefRepository;
import com.idq.cli.source.cre.etldb.repo.CreSourceMergeRepository;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of the CRE mapping, plus its case-move and de-duplication rules.
class CrePkeyTest {

    static final CreCareClientsService.Lookups NO_MERGES = new CreCareClientsService.Lookups(Map.of(), Set.of(),
            Set.of());

    static CreCareClientsService careClients() {
        return new CreCareClientsService(stub(CreCareClientsDeltaRepository.class), stub(CrePartyXrefRepository.class),
                stub(CrePartyHmrgRepository.class), stub(CreSourceMergeRepository.class),
                stub(CrePartyRepository.class), stub(CrePartyRoleRepository.class), stub(CreAddressRepository.class),
                stub(CrePhoneRepository.class), stub(CreAlternateIdRepository.class), stub(BadRecordRepository.class),
                new PassThroughAddressValidator());
    }

    /// The fixture reference data plus a CRE state that translates to `99` (outside the US).
    static EtlContext ctx() {
        return new EtlContext(CreCareClientsService.INFO, RUN, reference().withMasterCode("STATE", "CRE", "FC", "99"));
    }

    static CareClient client(String careId, String state, String maintFlag, String sourceId, String targetId,
            String rec, String recType) {
        return new CareClient(careId, DAY, "Ann", "Lee", null, DAY, "F", "1 Main St", "Austin", "227", state, "78701",
                "1234", "512-555-1234", "512345678", maintFlag, "123456789", DAY, "H", "W", sourceId, targetId, rec,
                recType);
    }

    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_CRE_CARE_Clients_pkey_test() {
        var out = careClients().transform(List.of(client("9100000001", "FC", null, null, null, null, "I")), NO_MERGES,
                ctx());

        assertThat(keys(out.rows(CreTargets.Party.class))).containsExactly("9100000001");
        assertThat(keys(out.rows(CreTargets.PartyRole.class))).containsExactly("9100000001|Member");
        assertThat(keys(out.rows(CreTargets.Address.class))).containsExactly("9100000001|Member|002");
        assertThat(keys(out.rows(CreTargets.Phone.class))).containsExactly(
                "9100000001|Member|Telephone|001|5125551234");
        assertThat(keys(out.rows(CreTargets.AlternateId.class))).containsExactly("9100000001|Member|022|9100000001",
                "9100000001|Member|002|512345678", "9100000001|Member|004|123456789");
        var address = out.rows(CreTargets.Address.class).getFirst().columns().validated();
        assertThat(address.addrLn1()).isEqualTo("1 Main St");
        assertThat(address.state()).isEqualTo("99");
        assertThat(address.cntryCd()).isEqualTo("ZZ");
        assertThat(address.county()).isEqualTo("996");
    }

    @Test
    void us_address_without_validator_score_is_an_exception() {
        var out = careClients().transform(List.of(client("9100000001", "TX", null, null, null, null, "I")), NO_MERGES,
                ctx());

        assertThat(out.rows(CreTargets.Address.class)).isEmpty();
        assertThat(out.badRecords()).extracting(BadRecord::attributeName).contains("Address");
    }

    @Test
    void case_move_without_merge_history_is_sent_to_mdm_and_keeps_the_target_id() {
        var lookups = new CreCareClientsService.Lookups(Map.of(
                "9100000005", new PartyXref("9100000005", "SRC_ROWID", "SRC_ORIG"),
                "9100000004", new PartyXref("9100000004", "TGT_ROWID", "TGT_ORIG")), Set.of(), Set.of());
        var moved = client("9100000005", "FC", "D", "9100000005", "9100000004", "CASEMOV", "B");
        var out = careClients().transform(List.of(moved), lookups, ctx());

        assertThat(out.rows(CreSources.SourceMerge.class)).containsExactly(
                new CreSources.SourceMerge("SRC_ROWID", "TGT_ROWID", RUN));
        assertThat(keys(out.rows(CreTargets.AlternateId.class))).contains("9100000005|Member|022|9100000004");
        var party = out.rows(CreTargets.Party.class).getFirst().audit();
        assertThat(party.periodStartDate()).isEqualTo(DAY.minusDays(1));
        assertThat(party.periodEndDate()).isEqualTo(DAY);
        assertThat(party.lastUpdateDate()).isEqualTo(RUN.minusHours(1));
    }

    @Test
    void merged_case_move_is_not_sent_again() {
        var lookups = new CreCareClientsService.Lookups(Map.of(
                "9100000005", new PartyXref("9100000005", "SRC_ROWID", "SRC_ORIG")), Set.of("SRC_ORIG"), Set.of());
        var moved = client("9100000005", "FC", "D", "9100000005", "9100000004", "CASEMOV", "B");
        var out = careClients().transform(List.of(moved), lookups, ctx());

        assertThat(out.rows(CreSources.SourceMerge.class)).isEmpty();
        assertThat(keys(out.rows(CreTargets.AlternateId.class))).contains("9100000005|Member|022|9100000005");
    }

    @Test
    void one_row_per_care_id_with_the_delta_row_first() {
        var target = client("9100000004", "FC", "D", "9100000005", "9100000004", "CASEMOV", "A");
        var delta = client("9100000004", "FC", null, null, null, null, "I");
        var out = careClients().transform(List.of(target, delta), NO_MERGES, ctx());

        assertThat(out.rows(CreTargets.Party.class)).singleElement()
                .satisfies(p -> assertThat(p.audit().periodEndDate()).isNull());
    }
}
