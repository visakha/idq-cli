package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static com.idq.cli.Fixtures.stub;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.rules.PassThroughAddressValidator;
import com.idq.cli.core.target.DqmAddressRepository;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.mdmdc.etldb.models.TrsTargets;
import com.idq.cli.mdmdc.etldb.repo.TrsAddressRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsEmailRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsManagedAttributeRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsPartyNameRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsPartyRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsPartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsPhoneRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsPlanRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsProviderRelationshipRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsRelationshipRepository;
import com.idq.cli.mdmdc.etldb.repo.TrsTypeOfAssistanceRepository;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AddressAssignment;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceSegment;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AuthorizedRepresentative;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.CaseContact;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.DistinctAddress;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.ManagedCarePlan;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberAlias;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberDemographics;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberIdentifiers;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberRelationship;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberSwitches;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.PrimaryCareProvider;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsCvMciEdgIndvToaDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcAliasDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcCasesDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcIndvDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcIndvHistRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcPrimaryPayeeDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsDcRelationshipsDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsInManagedCareDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsIndvAddrDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsPartyRoleAltIdRepository;
import com.idq.cli.source.trs.etldb.repo.TrsUniqueAddressDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsValidMemberRepository;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every TRS mapping, verified on the rows each mapping writes to its target.
class TrsPkeyTest {

    static TrsAddressService address() {
        return new TrsAddressService(stub(TrsIndvAddrDeltaRepository.class), stub(DqmAddressRepository.class),
                stub(TrsAddressRepository.class), stub(BadRecordRepository.class), null);
    }

    static TrsAlternateIdService alternateId() {
        return new TrsAlternateIdService(stub(TrsDcIndvDeltaRepository.class), stub(TrsDcIndvHistRepository.class),
                stub(TrsAlternateIdRepository.class), stub(BadRecordRepository.class), null);
    }

    static TrsAuthorizedRepresentativeService authorizedRepresentative() {
        return new TrsAuthorizedRepresentativeService(stub(TrsDcPrimaryPayeeDeltaRepository.class),
                stub(TrsManagedAttributeRepository.class), stub(BadRecordRepository.class));
    }

    static TrsMemberRelationshipService memberRelationship() {
        return new TrsMemberRelationshipService(stub(TrsDcRelationshipsDeltaRepository.class),
                stub(TrsRelationshipRepository.class), stub(BadRecordRepository.class), null);
    }

    static TrsPartyNameService partyName() {
        return new TrsPartyNameService(stub(TrsDcAliasDeltaRepository.class), stub(TrsPartyNameRepository.class),
                stub(BadRecordRepository.class), null);
    }

    static TrsPartyOnGoingService partyOnGoing() {
        return new TrsPartyOnGoingService(stub(TrsDcIndvDeltaRepository.class), stub(TrsValidMemberRepository.class),
                stub(TrsPartyRepository.class), stub(TrsPartyRoleRepository.class), stub(BadRecordRepository.class),
                null);
    }

    static TrsPhoneEmailService phoneEmail() {
        return new TrsPhoneEmailService(stub(TrsDcCasesDeltaRepository.class), stub(TrsPhoneRepository.class),
                stub(TrsEmailRepository.class), stub(BadRecordRepository.class), null);
    }

    static TrsPlanService plan() {
        return new TrsPlanService(stub(TrsInManagedCareDeltaRepository.class), stub(TrsPlanRepository.class),
                stub(BadRecordRepository.class), null);
    }

    static TrsPrimaryCareProviderService primaryCareProvider() {
        return new TrsPrimaryCareProviderService(stub(TrsInManagedCareDeltaRepository.class),
                stub(TrsPartyRoleAltIdRepository.class), stub(TrsProviderRelationshipRepository.class),
                stub(BadRecordRepository.class), null);
    }

    static TrsSwitchesService switches() {
        return new TrsSwitchesService(stub(TrsDcIndvDeltaRepository.class), stub(TrsManagedAttributeRepository.class),
                stub(BadRecordRepository.class), null);
    }

    static TrsTypeOfAssistanceService typeOfAssistance() {
        return new TrsTypeOfAssistanceService(stub(TrsCvMciEdgIndvToaDeltaRepository.class),
                stub(TrsTypeOfAssistanceRepository.class), stub(BadRecordRepository.class), null);
    }

    static TrsUniqueAddressService uniqueAddress() {
        return new TrsUniqueAddressService(stub(TrsIndvAddrDeltaRepository.class),
                stub(TrsUniqueAddressDeltaRepository.class), stub(BadRecordRepository.class),
                new PassThroughAddressValidator(), null);
    }


    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_OnGoing_pkey_test() {
        var daily = new MemberDemographics(123L, "ann", "b", "lee", null, null, "F", "W", "H", "Y", "Y",
                DAY.minusYears(30), DAY, "DC_INDV", null);
        var mci = new MemberDemographics(456L, "bob", null, "ray", null, null, "M", "W", "H", null, null,
                DAY.minusYears(40), DAY, "MCI", null);
        var out = partyOnGoing().transform(List.of(daily, mci), new TrsPartyOnGoingService.Lookups(Set.of()),
                ctx(TrsPartyOnGoingService.INFO));

        assertThat(keys(out.rows(TrsTargets.Party.class))).containsExactly("123|DC_INDV", "456");
        assertThat(keys(out.rows(TrsTargets.PartyRole.class))).containsExactly("123|DC_INDV|Member", "456|Member");
        assertThat(out.rows(TrsTargets.PartyRole.class)).extracting(r -> r.columns().ptyFk())
                .containsExactly("123|DC_INDV", "456");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing_pkey_test() {
        var out = authorizedRepresentative().transform(List.of(
                new AuthorizedRepresentative(123L, "Y", DAY.minusYears(1), null, DAY),
                new AuthorizedRepresentative(123L, "Y", DAY, null, DAY)), NoLookups.NONE,
                ctx(TrsAuthorizedRepresentativeService.INFO));

        assertThat(keys(out.rows(TrsTargets.ManagedAttribute.class))).containsExactly("123|Auth_Rep_Flag");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Nm_pkey_test() {
        var out = partyName().transform(List.of(
                new MemberAlias(123L, "123|DC_INDV", "Ann", null, "Lee", null, null, DAY, 2L),
                new MemberAlias(456L, "456", "Bob", null, null, null, null, DAY, 1L)), NoLookups.NONE,
                ctx(TrsPartyNameService.INFO));

        assertThat(keys(out.rows(TrsTargets.PartyName.class))).containsExactly("123|DC_INDV|002|2");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Rle_Alt_Id_pkey_test() {
        var row = new MemberIdentifiers("123456789|DC_INDV", "123456789", DAY, 512345678L, null);
        var out = alternateId().transform(List.of(row),
                new TrsAlternateIdService.Lookups(Set.of("123456789|512345678")), ctx(TrsAlternateIdService.INFO));

        assertThat(keys(out.rows(TrsTargets.AlternateId.class))).containsExactlyInAnyOrder(
                "123456789|DC_INDV|Member|002|123456789",
                "123456789|DC_INDV|Member|004|512345678",
                "123456789|DC_INDV|Member|007|123456789");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Rle_Pln_pkey_test() {
        var out = plan().transform(List.of(new ManagedCarePlan(123L, DAY, "PA", 1L, null, DAY),
                new ManagedCarePlan(456L, DAY, "ZZ", 1L, null, DAY)), NoLookups.NONE, ctx(TrsPlanService.INFO));

        assertThat(keys(out.rows(TrsTargets.Plan.class))).containsExactly("123|Member|PLN1");
        assertThat(out.badRecords()).extracting(b -> b.key().exceptionCode()).containsExactly("Invalid_Plan");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr_pkey_test() {
        var row = new CaseContact(123L, 9L, DAY, null, null, "Ann@Example.org", "(512) 555-1234", null, null, "123");
        var out = phoneEmail().transform(List.of(row), NoLookups.NONE, ctx(TrsPhoneEmailService.INFO));

        assertThat(keys(out.rows(TrsTargets.Phone.class))).containsExactly("123|Member|Telephone|001|5125551234");
        assertThat(keys(out.rows(TrsTargets.Email.class))).containsExactly("123|Member|001|Ann@Example.org");
        assertThat(out.rows(TrsTargets.Email.class).getFirst().columns().elecAddr()).isEqualTo("ann@example.org");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw_pkey_test() {
        var row = new MemberSwitches(123L, "Y", null, DAY, null, null, "123|DC_INDV", DAY, "DC_INDV");
        var out = switches().transform(List.of(row), NoLookups.NONE, ctx(TrsSwitchesService.INFO));

        assertThat(keys(out.rows(TrsTargets.ManagedAttribute.class))).containsExactly(
                "123|DC_INDV|File_Clearance_SW", "123|DC_INDV|Source_Table");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Rle_TOA_pkey_test() {
        var row = new AssistanceSegment("123", "A1", DAY, null, "MCI_EDG_INDV", "123", 77L, 9L, 3L, "MA", "EL",
                "TIERS", null, DAY);
        var out = typeOfAssistance().transform(List.of(row), NoLookups.NONE, ctx(TrsTypeOfAssistanceService.INFO));

        assertThat(keys(out.rows(TrsTargets.TypeOfAssistance.class))).containsExactly("123|Member|100|TIERS|77|MA|3");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem_pkey_test() {
        var row = new MemberRelationship(123L, 456L, DAY, null, "C", "PA", "123", "456|DC_INDV", "007", DAY, null);
        var out = memberRelationship().transform(List.of(row), NoLookups.NONE,
                ctx(TrsMemberRelationshipService.INFO));

        assertThat(keys(out.rows(TrsTargets.Relationship.class))).containsExactly(
                "123|Member|456|DC_INDV|Member|PAR");
    }

    @Test
    void m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP_pkey_test() {
        var row = new PrimaryCareProvider(123L, 1L, "S", DAY, DAY, "700000001", null, "123");
        var out = primaryCareProvider().transform(List.of(row),
                new TrsPrimaryCareProviderService.Lookups(Map.of("700000001", "700000001|HCO|Provider")),
                ctx(TrsPrimaryCareProviderService.INFO));

        var rows = out.rows(TrsTargets.ProviderRelationship.class);
        assertThat(keys(rows)).containsExactly("123|Member|700000001|HCO|100");
        assertThat(rows.getFirst().columns().relTypeCode()).isEqualTo("Member PCO");
    }

    @Test
    void m_Tgt_C_S_TRS_Addr_1_pkey_test() {
        var row = new DistinctAddress("1|||MAIN|NO|ST|||||AUSTIN|TX|78701|1234", "1", null, "MAIN", null, null,
                "AUSTIN", "TX", "78701", "1234", null, "ST", "NO");
        var out = uniqueAddress().transform(List.of(row),
                NoLookups.NONE, ctx(TrsUniqueAddressService.INFO));

        var unique = out.rows(TrsSources.UniqueAddressDelta.class).getFirst();
        assertThat(unique.addrId()).isEqualTo(row.addrId());
        assertThat(unique.srcAddrLn1()).isEqualTo("1  N MAIN St");
    }

    @Test
    void m_Tgt_C_S_TRS_Addr_2_pkey_test() {
        var row = new AddressAssignment(123L, 9L, 77L, "123", "MA", DAY, DAY, null, "id", "1 N MAIN ST", null,
                null, null, "AUSTIN", "453", "48", "US", "78701", "1234", null, null, null, null, null, null, null,
                null, null, null, null, null, null, null, null, null, null, null, "1 N MAIN ST", null, "AUSTIN",
                null, "TX", "US", "78701", "1234");
        var out = address().transform(List.of(row), NoLookups.NONE, ctx(TrsAddressService.INFO));

        assertThat(keys(out.rows(TrsTargets.Address.class))).containsExactly("123|Member|002|9|77|20260115");
    }
}
