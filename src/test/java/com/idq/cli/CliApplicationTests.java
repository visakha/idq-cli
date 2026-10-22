package com.idq.cli;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.workflow.MappingCatalog;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {"spring.shell.interactive.enabled=false", "spring.shell.context.close=false"})
class CliApplicationTests {

    @Autowired MappingCatalog catalog;

    @Test
    void contextLoadsWithEveryMapping() {
        assertThat(catalog.all()).hasSize(35);
        assertThat(catalog.all().getFirst().info().name()).isEqualTo("m_Tgt_C_S_TRS_Pty_OnGoing");
    }
}
