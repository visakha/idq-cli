package com.idq.cli.source.eci.etlmap.svc;

import com.idq.cli.core.ServiceMapping;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyAddress;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyContact;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.FamilyRelation;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyDemographics;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyIdentifier;
import com.idq.cli.source.eci.etldb.models.EciQueryRows.PartyName;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Registers the plain ECI services with the workflow runner (`wf_ECI_Stage_Load`, 013 to 018).
@Configuration
public class EciMappings {

    @Bean
    MemberMapping<?, ?> eciPartyValidationMapping(EciPartyValidationService service) {
        return new ServiceMapping<>(EciPartyValidationService.INFO, SubDomain.DEMOGRAPHICS, PartyName.class,
                service::fetchPartyNames, service::fetchValidationLookups, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> eciPartyMapping(EciPartyService service) {
        return new ServiceMapping<>(EciPartyService.INFO, SubDomain.DEMOGRAPHICS, PartyDemographics.class,
                service::fetchPartyDemographics, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> eciAddressMapping(EciAddressService service) {
        return new ServiceMapping<>(EciAddressService.INFO, SubDomain.ADDRESS, FamilyAddress.class,
                service::fetchFamilyAddresses, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> eciAlternateIdMapping(EciAlternateIdService service) {
        return new ServiceMapping<>(EciAlternateIdService.INFO, SubDomain.ALTERNATE_ID, PartyIdentifier.class,
                service::fetchPartyIdentifiers, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> eciPhoneEmailMapping(EciPhoneEmailService service) {
        return new ServiceMapping<>(EciPhoneEmailService.INFO, SubDomain.PHONE_EMAIL, FamilyContact.class,
                service::fetchFamilyContacts, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> eciRelationshipMapping(EciRelationshipService service) {
        return new ServiceMapping<>(EciRelationshipService.INFO, SubDomain.ROLE, FamilyRelation.class,
                service::fetchFamilyRelations, service::fetchRelationshipLookups, service::transform, service::load);
    }
}
