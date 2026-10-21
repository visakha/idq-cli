package com.idq.cli.source.wic;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static com.idq.cli.Fixtures.noInactive;
import static com.idq.cli.Fixtures.stub;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.rules.PassThroughAddressValidator;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.source.wic.WicQueries.ClientDemographics;
import com.idq.cli.source.wic.WicQueries.ClientIdentifier;
import com.idq.cli.source.wic.WicQueries.ClientName;
import com.idq.cli.source.wic.WicQueries.FamilyAddress;
import com.idq.cli.source.wic.WicQueries.FamilyContact;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every WIC mapping.
class WicPkeyTest {

    final WicQueries q = stub(WicQueries.class);

    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Validation_pkey_test() {
        var nameless = new ClientName("51", "Ann", null, null, DAY, DAY, "CLIENT", "0000000051", DAY);
        var out = new WicPartyValidation(q).transform(List.of(nameless),
                new WicPartyValidation.Lookups(InactiveStatus.Lookup.NONE, Map.of("0000000051", -1)),
                ctx(WicPartyValidation.INFO));

        assertThat(out.rows(WicTargets.InactiveStatus.class))
                .extracting(WicTargets.InactiveStatus::srcKey, WicTargets.InactiveStatus::deactivationSts)
                .containsExactly(org.assertj.core.groups.Tuple.tuple("0000000051", "D"));
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_pkey_test() {
        var row = new ClientDemographics("CLIENT", DAY, DAY, "51", "0000000051", "Ann", "Lee", null, DAY, "F",
                BigDecimal.ONE, BigDecimal.TEN, "ENG", "H", 1, 0, 0, 0, 0);
        var out = new WicParty(q).transform(List.of(row), noInactive(), ctx(WicParty.INFO));

        assertThat(keys(out.rows(WicTargets.Party.class))).containsExactly("0000000051");
        assertThat(keys(out.rows(WicTargets.PartyRole.class))).containsExactly("0000000051|Member");
        assertThat(out.rows(WicTargets.Party.class).getFirst().birthWghtGrms()).isEqualByComparingTo("283.5");
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Addr_pkey_test() {
        var row = new FamilyAddress("FAMILY", "51", "401", "0000000051", "1 Main St", null, "Houston", "Harris",
                "77002", DAY);
        var out = new WicAddress(q, new PassThroughAddressValidator()).transform(List.of(row), noInactive(),
                ctx(WicAddress.INFO));

        assertThat(keys(out.rows(WicTargets.Address.class))).containsExactly(
                "0000000051|Member|002|000000000401|1 MAIN ST||HOUSTON||77002");
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Rle_Alt_Id_pkey_test() {
        var out = new WicAlternateId(q).transform(List.of(new ClientIdentifier("51", DAY, "0000000051", "CLIENT"),
                new ClientIdentifier("401", DAY, "0000000401", "FAMILY")), noInactive(), ctx(WicAlternateId.INFO));

        assertThat(keys(out.rows(WicTargets.AlternateId.class))).containsExactly(
                "0000000051|Member|020|000000000051", "0000000401|Member|021|000000000401");
    }

    @Test
    void m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr_pkey_test() {
        var row = new FamilyContact("401", DAY, " 7135551234 ", "Ann@Example.org", "FAMILY", "0000000051", "51");
        var out = new WicPhoneEmail(q).transform(List.of(row), noInactive(), ctx(WicPhoneEmail.INFO));

        assertThat(keys(out.rows(WicTargets.Phone.class))).containsExactly(
                "0000000051|Member|Telephone|001|401|7135551234");
        assertThat(keys(out.rows(WicTargets.Email.class))).containsExactly(
                "0000000051|Member|001|401|Ann@Example.org");
    }
}
