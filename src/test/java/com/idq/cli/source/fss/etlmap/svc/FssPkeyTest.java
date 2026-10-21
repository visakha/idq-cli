package com.idq.cli.source.fss.etlmap.svc;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static com.idq.cli.Fixtures.noInactive;
import static com.idq.cli.Fixtures.stub;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.rules.PassThroughAddressValidator;
import com.idq.cli.core.target.DqmAddressRepository;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.mdmdc.etldb.models.FssTargets;
import com.idq.cli.mdmdc.etldb.repo.FssAddressRepository;
import com.idq.cli.mdmdc.etldb.repo.FssAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.FssEmailRepository;
import com.idq.cli.mdmdc.etldb.repo.FssPartyRepository;
import com.idq.cli.mdmdc.etldb.repo.FssPartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.FssPhoneRepository;
import com.idq.cli.mdmdc.etldb.repo.FssRelationshipRepository;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientAddress;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientContact;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientDemographics;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientIdentifier;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientName;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientRelation;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcRelationsViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssEtlSrcViewRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveLogRepository;
import com.idq.cli.source.fss.etldb.repo.FssInactiveStatusRepository;
import com.idq.cli.source.fss.etldb.repo.FssPartyXrefRepository;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every FSS mapping.
class FssPkeyTest {

    static FssAddressService address() {
        return new FssAddressService(stub(FssEtlSrcViewRepository.class), stub(FssInactiveStatusRepository.class),
                stub(DqmAddressRepository.class), stub(FssAddressRepository.class), stub(BadRecordRepository.class),
                new PassThroughAddressValidator(), null);
    }

    static FssAlternateIdService alternateId() {
        return new FssAlternateIdService(stub(FssEtlSrcViewRepository.class), stub(FssInactiveStatusRepository.class),
                stub(FssAlternateIdRepository.class), stub(BadRecordRepository.class), null);
    }

    static FssPartyService party() {
        return new FssPartyService(stub(FssEtlSrcViewRepository.class), stub(FssInactiveStatusRepository.class),
                stub(FssPartyRepository.class), stub(FssPartyRoleRepository.class), stub(BadRecordRepository.class),
                null);
    }

    static FssPartyValidationService partyValidation() {
        return new FssPartyValidationService(stub(FssEtlSrcViewRepository.class),
                stub(FssInactiveStatusRepository.class), stub(FssPartyXrefRepository.class),
                stub(FssInactiveLogRepository.class), stub(BadRecordRepository.class));
    }

    static FssPhoneEmailService phoneEmail() {
        return new FssPhoneEmailService(stub(FssEtlSrcViewRepository.class), stub(FssInactiveStatusRepository.class),
                stub(FssPhoneRepository.class), stub(FssEmailRepository.class), stub(BadRecordRepository.class), null);
    }

    static FssRelationshipService relationship() {
        return new FssRelationshipService(stub(FssEtlSrcRelationsViewRepository.class),
                stub(FssInactiveStatusRepository.class), stub(FssRelationshipRepository.class),
                stub(BadRecordRepository.class), null);
    }


    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_FSS_Pty_Validation_pkey_test() {
        var deleted = new ClientName("CLIENT", 11L, "0000000011", "Ann", "Lee", null, DAY, DAY, DAY, "D", "N");
        var back = new ClientName("CLIENT", 12L, "0000000012", "Bob", "Ray", null, DAY, DAY, DAY, "I", "N");
        var out = partyValidation().transform(List.of(deleted, back),
                new FssPartyValidationService.Lookups(new InactiveStatus.Lookup(Map.of("0000000012", "P")), Map.of()),
                ctx(FssPartyValidationService.INFO));

        assertThat(out.rows(FssSources.InactiveStatus.class))
                .extracting(FssSources.InactiveStatus::srcKey, FssSources.InactiveStatus::deactivationSts)
                .containsExactly(org.assertj.core.groups.Tuple.tuple("0000000012", null),
                        org.assertj.core.groups.Tuple.tuple("0000000011", "H"),
                        org.assertj.core.groups.Tuple.tuple("0000000012", "Reactivation"));
    }

    @Test
    void m_Tgt_C_S_FSS_Pty_pkey_test() {
        var row = new ClientDemographics("CLIENT", DAY, 11L, " 0000000011 ", "Ann", "Lee", null, DAY.minusYears(9),
                "F", "ENG", "H", 1, 0, 0, 0, 0, "JR");
        var out = party().transform(List.of(row), noInactive(), ctx(FssPartyService.INFO));

        assertThat(keys(out.rows(FssTargets.Party.class))).containsExactly("0000000011");
        assertThat(keys(out.rows(FssTargets.PartyRole.class))).containsExactly("0000000011|Member");
    }

    @Test
    void m_Tgt_C_S_FSS_Pty_Addr_pkey_test() {
        var row = new ClientAddress("CLIENT", 11L, 600L, "0000000011", "1 Main St", null, "Austin", "227", "tx",
                "78701", DAY, DAY);
        var out = address().transform(List.of(row), noInactive(),
                ctx(FssAddressService.INFO));

        assertThat(keys(out.rows(FssTargets.Address.class))).containsExactly(
                "0000000011|Member|002|0000000600|1 MAIN ST||AUSTIN|TX|78701");
    }

    @Test
    void m_Tgt_C_S_FSS_Pty_Rle_Alt_Id_pkey_test() {
        var client = new ClientIdentifier(11L, DAY, DAY, "0000000011", "CLIENT");
        var registration = new ClientIdentifier(12L, DAY, DAY, "0000000012", "REGIST");
        var out = alternateId().transform(List.of(client, registration), noInactive(),
                ctx(FssAlternateIdService.INFO));

        assertThat(keys(out.rows(FssTargets.AlternateId.class))).containsExactly(
                "0000000011|Member|022|0000000011", "0000000012|Member|023|0000000012");
    }

    @Test
    void m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr_pkey_test() {
        var row = new ClientContact(600L, DAY, "512-555-1234", "Ann@Example.org", "CLIENT", "0000000011", "12");
        var out = phoneEmail().transform(List.of(row), noInactive(), ctx(FssPhoneEmailService.INFO));

        assertThat(keys(out.rows(FssTargets.Phone.class))).containsExactly(
                "0000000011|Member|Telephone|001|0000000600|512-555-1234");
        assertThat(keys(out.rows(FssTargets.Email.class))).containsExactly(
                "0000000011|Member|001|0000000600|Ann@Example.org");
    }

    @Test
    void m_Tgt_C_S_FSS_Pty_Rle_Rel_pkey_test() {
        var row = new ClientRelation("To Child", 10L, "F", 11L, "0000000011", "0000000010", DAY, DAY, "MOTHER", "M",
                700L);
        var out = relationship().transform(List.of(row), noInactive(), ctx(FssRelationshipService.INFO));

        assertThat(keys(out.rows(FssTargets.Relationship.class))).containsExactly(
                "0000000010|Member|0000000011|Member|MTH");
    }
}
