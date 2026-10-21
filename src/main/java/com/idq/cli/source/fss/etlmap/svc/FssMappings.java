package com.idq.cli.source.fss.etlmap.svc;

import com.idq.cli.core.ServiceMapping;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientAddress;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientContact;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientDemographics;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientIdentifier;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientName;
import com.idq.cli.source.fss.etldb.models.FssQueryRows.ClientRelation;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Registers the plain FSS services with the workflow runner (`wf_FSS_Stage_Load`, 019 to 024).
@Configuration
public class FssMappings {

    @Bean
    MemberMapping<?, ?> fssAddressMapping(FssAddressService service) {
        return new ServiceMapping<>(FssAddressService.INFO, SubDomain.ADDRESS, ClientAddress.class,
                service::fetchClientAddresses, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> fssAlternateIdMapping(FssAlternateIdService service) {
        return new ServiceMapping<>(FssAlternateIdService.INFO, SubDomain.ALTERNATE_ID, ClientIdentifier.class,
                service::fetchClientIdentifiers, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> fssPartyMapping(FssPartyService service) {
        return new ServiceMapping<>(FssPartyService.INFO, SubDomain.DEMOGRAPHICS, ClientDemographics.class,
                service::fetchClientDemographics, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> fssPartyValidationMapping(FssPartyValidationService service) {
        return new ServiceMapping<>(FssPartyValidationService.INFO, SubDomain.DEMOGRAPHICS, ClientName.class,
                service::fetchClientNames, service::fetchValidationLookups, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> fssPhoneEmailMapping(FssPhoneEmailService service) {
        return new ServiceMapping<>(FssPhoneEmailService.INFO, SubDomain.PHONE_EMAIL, ClientContact.class,
                service::fetchClientContacts, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> fssRelationshipMapping(FssRelationshipService service) {
        return new ServiceMapping<>(FssRelationshipService.INFO, SubDomain.ROLE, ClientRelation.class,
                service::fetchClientRelations, service::fetchDeactivatedParties, service::transform, service::load);
    }
}
