package com.idq.cli.source.ttf.etlmap.svc;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static com.idq.cli.Fixtures.inactive;
import static com.idq.cli.Fixtures.noInactive;
import static com.idq.cli.Fixtures.stub;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.mdmdc.etldb.models.TtfTargets;
import com.idq.cli.mdmdc.etldb.repo.TtfAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.TtfPartyRepository;
import com.idq.cli.mdmdc.etldb.repo.TtfPartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.TtfPhoneRepository;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientDemographics;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientIdentifier;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientName;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientPhone;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import com.idq.cli.source.ttf.etldb.repo.TtfEtlSrcViewRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfInactiveLogRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfInactiveStatusRepository;
import com.idq.cli.source.ttf.etldb.repo.TtfPartyXrefRepository;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every TTF mapping.
class TtfPkeyTest {

    static TtfAlternateIdService alternateId() {
        return new TtfAlternateIdService(stub(TtfEtlSrcViewRepository.class), stub(TtfInactiveStatusRepository.class),
                stub(TtfAlternateIdRepository.class), stub(BadRecordRepository.class), null);
    }

    static TtfPartyService party() {
        return new TtfPartyService(stub(TtfEtlSrcViewRepository.class), stub(TtfInactiveStatusRepository.class),
                stub(TtfPartyRepository.class), stub(TtfPartyRoleRepository.class), stub(BadRecordRepository.class),
                null);
    }

    static TtfPartyValidationService partyValidation() {
        return new TtfPartyValidationService(stub(TtfEtlSrcViewRepository.class),
                stub(TtfInactiveStatusRepository.class), stub(TtfPartyXrefRepository.class),
                stub(TtfInactiveLogRepository.class), stub(BadRecordRepository.class));
    }

    static TtfPhoneService phone() {
        return new TtfPhoneService(stub(TtfEtlSrcViewRepository.class), stub(TtfInactiveStatusRepository.class),
                stub(TtfPhoneRepository.class), stub(BadRecordRepository.class), null);
    }


    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_Validation_pkey_test() {
        var declined = new ClientName(31L, "DECLINED", "Lee", null, DAY, DAY, DAY, "Y");
        var out = partyValidation().transform(List.of(declined),
                new TtfPartyValidationService.Lookups(InactiveStatus.Lookup.NONE, Map.of()), ctx(TtfPartyValidationService.INFO));

        assertThat(out.rows(TtfSources.InactiveStatus.class)).extracting(TtfSources.InactiveStatus::srcKey)
                .containsExactly("0000000031");
        assertThat(out.badRecords()).extracting(b -> b.key().exceptionCode()).containsExactly("Invalid_First_Name");
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_pkey_test() {
        var row = new ClientDemographics(DAY, DAY, 31L, "0000000031", "Ann", "Lee", null, DAY.minusYears(20), "33",
                "55");
        var out = party().transform(List.of(row), noInactive(), ctx(TtfPartyService.INFO));

        assertThat(keys(out.rows(TtfTargets.Party.class))).containsExactly("0000000031");
        assertThat(keys(out.rows(TtfTargets.PartyRole.class))).containsExactly("0000000031|Member");
        assertThat(out.rows(TtfTargets.Party.class).getFirst().columns().gndrCd()).isEqualTo("2");
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_Rle_Alt_Id_pkey_test() {
        var out = alternateId().transform(List.of(new ClientIdentifier(31L, DAY, "0000000031"),
                new ClientIdentifier(32L, DAY, "0000000032")), inactive("0000000032"), ctx(TtfAlternateIdService.INFO));

        assertThat(keys(out.rows(TtfTargets.AlternateId.class))).containsExactly("0000000031|Member|024|0000000031");
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_Rle_Phn_pkey_test() {
        var out = phone().transform(List.of(new ClientPhone(DAY, "(214) 555-1234", "0000000031")),
                noInactive(), ctx(TtfPhoneService.INFO));

        var phones = out.rows(TtfTargets.Phone.class);
        assertThat(keys(phones)).containsExactly("0000000031|Member|Telephone|001|(214) 555-1234");
        assertThat(phones.getFirst().columns().phnNum()).isEqualTo("2145551234");
    }
}
