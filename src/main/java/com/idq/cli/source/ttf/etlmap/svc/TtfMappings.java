package com.idq.cli.source.ttf.etlmap.svc;

import com.idq.cli.core.ServiceMapping;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientDemographics;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientIdentifier;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientName;
import com.idq.cli.source.ttf.etldb.models.TtfQueryRows.ClientPhone;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Registers the plain TTF services with the workflow runner (`wf_TTF_Stage_Load`, 025 to 028).
@Configuration
public class TtfMappings {

    @Bean
    MemberMapping<?, ?> ttfAlternateIdMapping(TtfAlternateIdService service) {
        return new ServiceMapping<>(TtfAlternateIdService.INFO, SubDomain.ALTERNATE_ID, ClientIdentifier.class,
                service::fetchClientIdentifiers, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> ttfPartyMapping(TtfPartyService service) {
        return new ServiceMapping<>(TtfPartyService.INFO, SubDomain.DEMOGRAPHICS, ClientDemographics.class,
                service::fetchClientDemographics, service::fetchDeactivatedParties, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> ttfPartyValidationMapping(TtfPartyValidationService service) {
        return new ServiceMapping<>(TtfPartyValidationService.INFO, SubDomain.DEMOGRAPHICS, ClientName.class,
                service::fetchClientNames, service::fetchValidationLookups, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> ttfPhoneMapping(TtfPhoneService service) {
        return new ServiceMapping<>(TtfPhoneService.INFO, SubDomain.PHONE_EMAIL, ClientPhone.class,
                service::fetchClientPhones, service::fetchDeactivatedParties, service::transform, service::load);
    }
}
