package com.idq.cli.source.wic.etlmap.svc;

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
import com.idq.cli.mdmdc.etldb.models.WicTargets;
import com.idq.cli.mdmdc.etldb.repo.WicAddressRepository;
import com.idq.cli.mdmdc.etldb.repo.WicAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.WicEmailRepository;
import com.idq.cli.mdmdc.etldb.repo.WicPartyRepository;
import com.idq.cli.mdmdc.etldb.repo.WicPartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.WicPhoneRepository;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientDemographics;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientIdentifier;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientName;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyAddress;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyContact;
import com.idq.cli.source.wic.etldb.models.WicSources;
import com.idq.cli.source.wic.etldb.repo.WicEtlSrcViewRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveLogRepository;
import com.idq.cli.source.wic.etldb.repo.WicInactiveStatusRepository;
import com.idq.cli.source.wic.etldb.repo.WicPartyXrefRepository;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every WIC mapping.
class WicPkeyTest {

    static WicAddressService address() {
        return new WicAddressService(stub(WicEtlSrcViewRepository.class), stub(WicInactiveStatusRepository.class),
                stub(DqmAddressRepository.class), stub(WicAddressRepository.class), stub(BadRecordRepository.class),
                new PassThroughAddressValidator(), null);
    }

    static WicAlternateIdService alternateId() {
        return new WicAlternateIdService(stub(WicEtlSrcViewRepository.class), stub(WicInactiveStatusRepository.class),
                stub(WicAlternateIdRepository.class), stub(BadRecordRepository.class), null);
    }

    static WicPartyService party() {
        return new WicPartyService(stub(WicEtlSrcViewRepository.class), stub(WicInactiveStatusRepository.class),
                stub(WicPartyRepository.class), stub(WicPartyRoleRepository.class), stub(BadRecordRepository.class),
                null);
    }

    static WicPartyValidationService partyValidation() {
        return new WicPartyValidationService(stub(WicEtlSrcViewRepository.class),
                stub(WicInactiveStatusRepository.class), stub(WicPartyXrefRepository.class),
                stub(WicInactiveLogRepository.class), stub(BadRecordRepository.class));
    }

    static WicPhoneEmailService phoneEmail() {
        return new WicPhoneEmailService(stub(WicEtlSrcViewRepository.class), stub(WicInactiveStatusRepository.class),
                stub(WicPhoneRepository.class), stub(WicEmailRepository.class), stub(BadRecordRepository.class), null);
    }


    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Validation_pkey_test() {
        var nameless = new ClientName("51", "Ann", null, null, DAY, DAY, "CLIENT", "0000000051", DAY);
        var out = partyValidation().transform(List.of(nameless),
                new WicPartyValidationService.Lookups(InactiveStatus.Lookup.NONE, Map.of("0000000051", -1)),
                ctx(WicPartyValidationService.INFO));

        assertThat(out.rows(WicSources.InactiveStatus.class))
                .extracting(WicSources.InactiveStatus::srcKey, WicSources.InactiveStatus::deactivationSts)
                .containsExactly(org.assertj.core.groups.Tuple.tuple("0000000051", "D"));
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_pkey_test() {
        var row = new ClientDemographics("CLIENT", DAY, DAY, "51", "0000000051", "Ann", "Lee", null, DAY, "F",
                BigDecimal.ONE, BigDecimal.TEN, "ENG", "H", 1, 0, 0, 0, 0);
        var out = party().transform(List.of(row), noInactive(), ctx(WicPartyService.INFO));

        assertThat(keys(out.rows(WicTargets.Party.class))).containsExactly("0000000051");
        assertThat(keys(out.rows(WicTargets.PartyRole.class))).containsExactly("0000000051|Member");
        assertThat(out.rows(WicTargets.Party.class).getFirst().birthWghtGrms()).isEqualByComparingTo("283.5");
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Addr_pkey_test() {
        var row = new FamilyAddress("FAMILY", "51", "401", "0000000051", "1 Main St", null, "Houston", "Harris",
                "77002", DAY);
        var out = address().transform(List.of(row), noInactive(),
                ctx(WicAddressService.INFO));

        assertThat(keys(out.rows(WicTargets.Address.class))).containsExactly(
                "0000000051|Member|002|000000000401|1 MAIN ST||HOUSTON||77002");
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Rle_Alt_Id_pkey_test() {
        var out = alternateId().transform(List.of(new ClientIdentifier("51", DAY, "0000000051", "CLIENT"),
                new ClientIdentifier("401", DAY, "0000000401", "FAMILY")), noInactive(), ctx(WicAlternateIdService.INFO));

        assertThat(keys(out.rows(WicTargets.AlternateId.class))).containsExactly(
                "0000000051|Member|020|000000000051", "0000000401|Member|021|000000000401");
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr_pkey_test() {
        var row = new FamilyContact("401", DAY, " 7135551234 ", "Ann@Example.org", "FAMILY", "0000000051", "51");
        var out = phoneEmail().transform(List.of(row), noInactive(), ctx(WicPhoneEmailService.INFO));

        assertThat(keys(out.rows(WicTargets.Phone.class))).containsExactly(
                "0000000051|Member|Telephone|001|401|7135551234");
        assertThat(keys(out.rows(WicTargets.Email.class))).containsExactly(
                "0000000051|Member|001|401|Ann@Example.org");
    }
}
