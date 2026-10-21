package com.idq.cli.source.wic.etlmap.svc;

import com.idq.cli.core.ServiceMapping;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientDemographics;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientIdentifier;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.ClientName;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyAddress;
import com.idq.cli.source.wic.etldb.models.WicQueryRows.FamilyContact;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Registers the plain WIC services with the workflow runner (`wf_WIC_Stage_Load`, 029 to 033).
@Configuration
public class WicMappings {

    @Bean
    MemberMapping<?, ?> wicAddressMapping(WicAddressService service) {
        return new ServiceMapping<>(WicAddressService.INFO, SubDomain.ADDRESS, FamilyAddress.class,
                service::fetchFamilyAddresses, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> wicAlternateIdMapping(WicAlternateIdService service) {
        return new ServiceMapping<>(WicAlternateIdService.INFO, SubDomain.ALTERNATE_ID, ClientIdentifier.class,
                service::fetchClientIdentifiers, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> wicPartyMapping(WicPartyService service) {
        return new ServiceMapping<>(WicPartyService.INFO, SubDomain.DEMOGRAPHICS, ClientDemographics.class,
                service::fetchClientDemographics, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> wicPartyValidationMapping(WicPartyValidationService service) {
        return new ServiceMapping<>(WicPartyValidationService.INFO, SubDomain.DEMOGRAPHICS, ClientName.class,
                service::fetchClientNames, service::fetchValidationLookups, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> wicPhoneEmailMapping(WicPhoneEmailService service) {
        return new ServiceMapping<>(WicPhoneEmailService.INFO, SubDomain.PHONE_EMAIL, FamilyContact.class,
                service::fetchFamilyContacts, service::fetchDeactivatedParties, service::transform, service::load);
    }
}
