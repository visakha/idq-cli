package com.idq.cli.source.trs.etlmap.svc;

import com.idq.cli.core.ServiceMapping;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AddressAssignment;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceSegment;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AssistanceType;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.AuthorizedRepresentative;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.CaseContact;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.DistinctAddress;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.ManagedCarePlan;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberAlias;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberDemographics;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberIdentifiers;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberRelationship;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.MemberSwitches;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.PrimaryCareProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Registers the plain TRS services with the workflow runner (`wf_TRS_Stage_Load_1_Ongoing`, 001 to 012, and
/// `wf_TRS_Stage_Load_TOA`, 035).
@Configuration
public class TrsMappings {

    @Bean
    MemberMapping<?, ?> trsAddressMapping(TrsAddressService service) {
        return new ServiceMapping<>(TrsAddressService.INFO, SubDomain.ADDRESS, AddressAssignment.class,
                service::fetchAddressAssignments, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsAlternateIdMapping(TrsAlternateIdService service) {
        return new ServiceMapping<>(TrsAlternateIdService.INFO, SubDomain.ALTERNATE_ID, MemberIdentifiers.class,
                service::fetchMemberIdentifiers, service::fetchValidSsns, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsAuthorizedRepresentativeMapping(TrsAuthorizedRepresentativeService service) {
        return new ServiceMapping<>(TrsAuthorizedRepresentativeService.INFO, SubDomain.PARTY_MANAGED_ATTRIB,
                AuthorizedRepresentative.class, service::fetchAuthorizedRepresentatives, NoLookups::none,
                service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsMemberRelationshipMapping(TrsMemberRelationshipService service) {
        return new ServiceMapping<>(TrsMemberRelationshipService.INFO, SubDomain.ROLE, MemberRelationship.class,
                service::fetchMemberRelationships, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsPartyNameMapping(TrsPartyNameService service) {
        return new ServiceMapping<>(TrsPartyNameService.INFO, SubDomain.ALTERNATE_NAME, MemberAlias.class,
                service::fetchMemberAliases, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsPartyOnGoingMapping(TrsPartyOnGoingService service) {
        return new ServiceMapping<>(TrsPartyOnGoingService.INFO, SubDomain.DEMOGRAPHICS, MemberDemographics.class,
                service::fetchMemberDemographics, service::fetchKnownValidMembers, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsPhoneEmailMapping(TrsPhoneEmailService service) {
        return new ServiceMapping<>(TrsPhoneEmailService.INFO, SubDomain.PHONE_EMAIL, CaseContact.class,
                service::fetchCaseContacts, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsPlanMapping(TrsPlanService service) {
        return new ServiceMapping<>(TrsPlanService.INFO, SubDomain.ROLE, ManagedCarePlan.class,
                service::fetchManagedCarePlans, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsPrimaryCareProviderMapping(TrsPrimaryCareProviderService service) {
        return new ServiceMapping<>(TrsPrimaryCareProviderService.INFO, SubDomain.ROLE, PrimaryCareProvider.class,
                service::fetchPrimaryCareProviders, service::fetchProviderKeys, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsSwitchesMapping(TrsSwitchesService service) {
        return new ServiceMapping<>(TrsSwitchesService.INFO, SubDomain.PARTY_MANAGED_ATTRIB, MemberSwitches.class,
                service::fetchMemberSwitches, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsTypeOfAssistanceMapping(TrsTypeOfAssistanceService service) {
        return new ServiceMapping<>(TrsTypeOfAssistanceService.INFO, SubDomain.ROLE, AssistanceSegment.class,
                service::fetchAssistanceSegments, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsTypeOfAssistanceCatalogueMapping(TrsTypeOfAssistanceCatalogueService service) {
        return new ServiceMapping<>(TrsTypeOfAssistanceCatalogueService.INFO, SubDomain.REFERENCE, AssistanceType.class,
                service::fetchAssistanceTypes, NoLookups::none, service::transform, service::load);
    }

    @Bean
    MemberMapping<?, ?> trsUniqueAddressMapping(TrsUniqueAddressService service) {
        return new ServiceMapping<>(TrsUniqueAddressService.INFO, SubDomain.ADDRESS, DistinctAddress.class,
                service::fetchDistinctAddresses, NoLookups::none, service::transform, service::load);
    }
}
