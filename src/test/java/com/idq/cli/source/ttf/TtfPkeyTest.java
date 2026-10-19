package com.idq.cli.source.ttf;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static com.idq.cli.Fixtures.inactive;
import static com.idq.cli.Fixtures.noInactive;
import static com.idq.cli.Fixtures.queries;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.source.ttf.TtfQueries.ClientDemographics;
import com.idq.cli.source.ttf.TtfQueries.ClientIdentifier;
import com.idq.cli.source.ttf.TtfQueries.ClientName;
import com.idq.cli.source.ttf.TtfQueries.ClientPhone;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every TTF mapping.
class TtfPkeyTest {

    final TtfQueries q = queries(TtfQueries.class);

    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_Validation_pkey_test() {
        var declined = new ClientName(31L, "DECLINED", "Lee", null, DAY, DAY, DAY, "Y");
        var out = new TtfPartyValidation(q).transform(List.of(declined),
                new TtfPartyValidation.Lookups(InactiveStatus.Lookup.NONE, Map.of()), ctx(TtfPartyValidation.INFO));

        assertThat(out.rows(TtfTargets.InactiveStatus.class)).extracting(TtfTargets.InactiveStatus::srcKey)
                .containsExactly("0000000031");
        assertThat(out.badRecords()).extracting(b -> b.exceptionCode()).containsExactly("Invalid_First_Name");
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_pkey_test() {
        var row = new ClientDemographics(DAY, DAY, 31L, "0000000031", "Ann", "Lee", null, DAY.minusYears(20), "33",
                "55");
        var out = new TtfParty(q).transform(List.of(row), noInactive(), ctx(TtfParty.INFO));

        assertThat(keys(out.rows(TtfTargets.Party.class))).containsExactly("0000000031");
        assertThat(keys(out.rows(TtfTargets.PartyRole.class))).containsExactly("0000000031|Member");
        assertThat(out.rows(TtfTargets.Party.class).getFirst().columns().gndrCd()).isEqualTo("2");
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_Rle_Alt_Id_pkey_test() {
        var out = new TtfAlternateId(q).transform(List.of(new ClientIdentifier(31L, DAY, "0000000031"),
                new ClientIdentifier(32L, DAY, "0000000032")), inactive("0000000032"), ctx(TtfAlternateId.INFO));

        assertThat(keys(out.rows(TtfTargets.AlternateId.class))).containsExactly("0000000031|Member|024|0000000031");
    }

    @Test
    void m_Tgt_C_S_TTF_Pty_Rle_Phn_pkey_test() {
        var out = new TtfPhone(q).transform(List.of(new ClientPhone(DAY, "(214) 555-1234", "0000000031")),
                noInactive(), ctx(TtfPhone.INFO));

        var phones = out.rows(TtfTargets.Phone.class);
        assertThat(keys(phones)).containsExactly("0000000031|Member|Telephone|001|(214) 555-1234");
        assertThat(phones.getFirst().columns().phnNum()).isEqualTo("2145551234");
    }
}
