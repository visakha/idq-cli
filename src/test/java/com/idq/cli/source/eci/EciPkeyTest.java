package com.idq.cli.source.eci;

import static com.idq.cli.Fixtures.DAY;
import static com.idq.cli.Fixtures.ctx;
import static com.idq.cli.Fixtures.noInactive;
import static com.idq.cli.Fixtures.queries;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.InactiveStatus;
import com.idq.cli.core.rules.PassThroughAddressValidator;
import com.idq.cli.core.target.StagingRow;
import com.idq.cli.source.eci.EciQueries.FamilyAddress;
import com.idq.cli.source.eci.EciQueries.FamilyContact;
import com.idq.cli.source.eci.EciQueries.FamilyRelation;
import com.idq.cli.source.eci.EciQueries.PartyDemographics;
import com.idq.cli.source.eci.EciQueries.PartyIdentifier;
import com.idq.cli.source.eci.EciQueries.PartyName;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every ECI mapping.
class EciPkeyTest {

    final EciQueries q = queries(EciQueries.class);

    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Validation_pkey_test() {
        var complete = new PartyName("ECI_CHILD", 42L, "Ann", "Lee", null, DAY, DAY, null, null, null, DAY);
        var nameless = new PartyName("ECI_FAMILY", 7L, null, "Lee", null, DAY, DAY, null, null, null, DAY);
        var out = new EciPartyValidation(q).transform(List.of(complete, nameless),
                new EciPartyValidation.Lookups(new InactiveStatus.Lookup(Map.of("0000000042", "P")), Map.of(),
                        Set.of(), Set.of()), ctx(EciPartyValidation.INFO));

        assertThat(out.rows(EciTargets.InactiveStatus.class)).extracting(EciTargets.InactiveStatus::srcKey)
                .containsExactly("0000000042", "0000000007F");
        assertThat(out.rows(EciTargets.InactiveLog.class)).extracting(EciTargets.InactiveLog::action)
                .containsExactly("Reactivation", "Deactivation");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_pkey_test() {
        var child = new PartyDemographics("ECI_CHILD", 42L, null, "Ann", "Lee", "B", DAY.minusYears(2), null, "F",
                BigDecimal.valueOf(7), BigDecimal.valueOf(4), null, "ENG", null, DAY, DAY, "u", "u", "H", 1, 0, 0, 0,
                0, DAY);
        var family = new PartyDemographics("ECI_FAMILY", 42L, null, "Mia", "Lee", null, DAY.minusYears(30), null, "F",
                null, null, null, null, null, DAY, DAY, "u", "u", null, null, null, null, null, null, DAY);
        var out = new EciParty(q).transform(List.of(child, family), noInactive(), ctx(EciParty.INFO));

        assertThat(keys(out.rows(EciTargets.Party.class))).containsExactly("0000000042", "0000000042F");
        assertThat(keys(out.rows(EciTargets.PartyRole.class))).containsExactly("0000000042|Member",
                "0000000042F|Member");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Addr_pkey_test() {
        var row = new FamilyAddress("ECI_FAMILY", 42L, 5L, "1 Main St", null, "1", "Austin", "Travis", "tx",
                "78701", "1234", DAY);
        var out = new EciAddress(q, new PassThroughAddressValidator()).transform(List.of(row), noInactive(),
                ctx(EciAddress.INFO));

        assertThat(keys(out.rows(EciTargets.Address.class))).containsExactly(
                "0000000042F|Member|002|0000000005|1 MAIN ST||AUSTIN|TX|78701|1234");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Rle_Alt_Id_pkey_test() {
        var childId = new PartyIdentifier(42L, "0000000042|Member", "0000000042", "018", "0000000042", DAY, null,
                "0000000042|Member|018|0000000042");
        var badSsn = new PartyIdentifier(42L, "0000000042|Member", "0000000042", "004", "000123456", DAY, null,
                "0000000042|Member|004|0000000042");
        var out = new EciAlternateId(q).transform(List.of(childId, badSsn), noInactive(), ctx(EciAlternateId.INFO));

        assertThat(keys(out.rows(EciTargets.AlternateId.class))).containsExactly("0000000042|Member|018|0000000042");
        assertThat(out.badRecords()).extracting(b -> b.exceptionCode()).containsExactly("Invalid_SSN");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr_pkey_test() {
        var phone = new FamilyContact("ECI_FAMILY", "P1", 3L, "42", DAY, "PHONE", "5125551234", null, "Telephone",
                "001", "Primary");
        var email = new FamilyContact("ECI_CHILD", "E1", 3L, "42", DAY, "EADDRESS", " a@b.org ", null, null, null,
                null);
        var out = new EciPhoneEmail(q).transform(List.of(phone, email), noInactive(), ctx(EciPhoneEmail.INFO));

        assertThat(keys(out.rows(EciTargets.Phone.class))).containsExactly("42F|Member|Telephone|001|P1|5125551234");
        assertThat(keys(out.rows(EciTargets.Email.class))).containsExactly("42|Member|001|E1|a@b.org");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Rle_Rel_pkey_test() {
        var toChild = new FamilyRelation("To Child", 7L, "F", 42L, "1", DAY, DAY);
        var out = new EciRelationship(q).transform(List.of(toChild),
                new EciRelationship.Lookups(noInactive(), Map.of("42", "M")), ctx(EciRelationship.INFO));

        assertThat(keys(out.rows(EciTargets.Relationship.class))).containsExactly(
                "0000000007F|Member|0000000042|Member|MTH");
    }
}
