package com.idq.cli.source.eci.etlmap.svc;

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
import com.idq.cli.mdmdc.etldb.models.EciTargets;
import com.idq.cli.mdmdc.etldb.repo.EciAddressRepository;
import com.idq.cli.mdmdc.etldb.repo.EciAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.EciEmailRepository;
import com.idq.cli.mdmdc.etldb.repo.EciPartyRepository;
import com.idq.cli.mdmdc.etldb.repo.EciPartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.EciPhoneRepository;
import com.idq.cli.mdmdc.etldb.repo.EciRelationshipRepository;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyAddress;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyContact;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyRelation;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyDemographics;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyIdentifier;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyName;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.eci.etldb.repo.EciChildDeltaRepository;
import com.idq.cli.source.eci.etldb.repo.EciDupCasesViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciFamilyAddressViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciFamilyDeltaRepository;
import com.idq.cli.source.eci.etldb.repo.EciFamilyPhoneViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciFamilyValidationViewRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveLogRepository;
import com.idq.cli.source.eci.etldb.repo.EciInactiveStatusRepository;
import com.idq.cli.source.eci.etldb.repo.EciPartyXrefRepository;
import com.idq.cli.source.eci.etldb.repo.EciSnChildRepository;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;

/// `PKEY_SRC_OBJECT` formulation of every ECI mapping.
public class EciPkeyTest {

    final EciInactiveStatusRepository inactiveStatuses = stub(EciInactiveStatusRepository.class);
    final BadRecordRepository badRecords = stub(BadRecordRepository.class);

    /// The relationship service on stub repositories; the audit report test uses it too.
    public static EciRelationshipService relationships() {
        return new EciRelationshipService(stub(EciFamilyDeltaRepository.class),
                stub(EciInactiveStatusRepository.class), stub(EciSnChildRepository.class),
                stub(EciRelationshipRepository.class), stub(BadRecordRepository.class), null);
    }

    static List<String> keys(List<? extends StagingRow<?>> rows) {
        return rows.stream().map(StagingRow::pkeySrcObject).toList();
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Validation_pkey_test() {
        var complete = new PartyName("ECI_CHILD", 42L, "Ann", "Lee", null, DAY, DAY, null, null, null, DAY);
        var nameless = new PartyName("ECI_FAMILY", 7L, null, "Lee", null, DAY, DAY, null, null, null, DAY);
        var out = new EciPartyValidationService(stub(EciChildDeltaRepository.class),
                inactiveStatuses, stub(EciInactiveLogRepository.class), stub(EciPartyXrefRepository.class),
                stub(EciDupCasesViewRepository.class), stub(EciFamilyValidationViewRepository.class), badRecords)
                .transform(List.of(complete, nameless),
                new EciPartyValidationService.Lookups(new InactiveStatus.Lookup(Map.of("0000000042", "P")), Map.of(),
                        Set.of(), Set.of()), ctx(EciPartyValidationService.INFO));

        // The reactivated party (0000000042) is only logged: its status row is never deleted, so no row for it here.
        assertThat(out.rows(EciSources.InactiveStatus.class)).extracting(EciSources.InactiveStatus::srcKey)
                .containsExactly("0000000007F");
        assertThat(out.rows(EciSources.InactiveLog.class)).extracting(EciSources.InactiveLog::action)
                .containsExactly("Reactivation", "Deactivation");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_pkey_test() {
        var child = new PartyDemographics("ECI_CHILD", 42L, null, "Ann", "Lee", "B", DAY.minusYears(2), null, "F",
                BigDecimal.valueOf(7), BigDecimal.valueOf(4), null, "ENG", null, DAY, DAY, "u", "u", "H", 1, 0, 0, 0,
                0, DAY);
        var family = new PartyDemographics("ECI_FAMILY", 42L, null, "Mia", "Lee", null, DAY.minusYears(30), null, "F",
                null, null, null, null, null, DAY, DAY, "u", "u", null, null, null, null, null, null, DAY);
        var out = new EciPartyService(stub(EciChildDeltaRepository.class), inactiveStatuses,
                stub(EciPartyRepository.class), stub(EciPartyRoleRepository.class), badRecords, null)
                .transform(List.of(child, family), noInactive(), ctx(EciPartyService.INFO));

        assertThat(keys(out.rows(EciTargets.Party.class))).containsExactly("0000000042", "0000000042F");
        assertThat(keys(out.rows(EciTargets.PartyRole.class))).containsExactly("0000000042|Member",
                "0000000042F|Member");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Addr_pkey_test() {
        var row = new FamilyAddress("ECI_FAMILY", 42L, 5L, "1 Main St", null, "1", "Austin", "Travis", "tx",
                "78701", "1234", DAY);
        var out = new EciAddressService(stub(EciFamilyAddressViewRepository.class), inactiveStatuses,
                stub(EciAddressRepository.class), stub(DqmAddressRepository.class), badRecords,
                new PassThroughAddressValidator(), null).transform(List.of(row), noInactive(),
                ctx(EciAddressService.INFO));

        assertThat(keys(out.rows(EciTargets.Address.class))).containsExactly(
                "0000000042F|Member|002|0000000005|1 MAIN ST||AUSTIN|TX|78701|1234");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Rle_Alt_Id_pkey_test() {
        var childId = new PartyIdentifier(42L, "0000000042|Member", "0000000042", "018", "0000000042", DAY, null,
                "0000000042|Member|018|0000000042");
        var badSsn = new PartyIdentifier(42L, "0000000042|Member", "0000000042", "004", "000123456", DAY, null,
                "0000000042|Member|004|0000000042");
        var out = new EciAlternateIdService(stub(EciChildDeltaRepository.class), inactiveStatuses,
                stub(EciAlternateIdRepository.class), badRecords, null)
                .transform(List.of(childId, badSsn), noInactive(), ctx(EciAlternateIdService.INFO));

        assertThat(keys(out.rows(EciTargets.AlternateId.class))).containsExactly("0000000042|Member|018|0000000042");
        assertThat(out.badRecords()).extracting(b -> b.key().exceptionCode()).containsExactly("Invalid_SSN");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr_pkey_test() {
        var phone = new FamilyContact("ECI_FAMILY", "P1", 3L, "42", DAY, "PHONE", "5125551234", null, "Telephone",
                "001", "Primary");
        var email = new FamilyContact("ECI_CHILD", "E1", 3L, "42", DAY, "EADDRESS", " a@b.org ", null, null, null,
                null);
        var out = new EciPhoneEmailService(stub(EciFamilyPhoneViewRepository.class), inactiveStatuses,
                stub(EciPhoneRepository.class), stub(EciEmailRepository.class), badRecords, null)
                .transform(List.of(phone, email), noInactive(), ctx(EciPhoneEmailService.INFO));

        assertThat(keys(out.rows(EciTargets.Phone.class))).containsExactly("42F|Member|Telephone|001|P1|5125551234");
        assertThat(keys(out.rows(EciTargets.Email.class))).containsExactly("42|Member|001|E1|a@b.org");
    }

    @Test
    void m_Tgt_C_S_ECI_Pty_Rle_Rel_pkey_test() {
        var toChild = new FamilyRelation("To Child", 7L, "F", 42L, "1", DAY, DAY);
        var out = relationships().transform(List.of(toChild),
                new EciRelationshipService.Lookups(noInactive(), Map.of("42", "M")), ctx(EciRelationshipService.INFO));

        assertThat(keys(out.rows(EciTargets.Relationship.class))).containsExactly(
                "0000000007F|Member|0000000042|Member|MTH");
    }
}
