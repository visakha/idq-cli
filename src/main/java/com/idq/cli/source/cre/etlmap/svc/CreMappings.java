package com.idq.cli.source.cre.etlmap.svc;

import com.idq.cli.core.ServiceMapping;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.SubDomain;
import com.idq.cli.source.cre.etldb.models.CreQueryRows.CareClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Registers the plain CRE service with the workflow runner (`wf_CRE_Stage_Load_Ongoing`, 034).
@Configuration
public class CreMappings {

    @Bean
    MemberMapping<?, ?> creCareClientsMapping(CreCareClientsService service) {
        return new ServiceMapping<>(CreCareClientsService.INFO, SubDomain.DEMOGRAPHICS, CareClient.class,
                service::fetchCareClients, service::fetchMergeLookups, service::transform, service::load);
    }
}
