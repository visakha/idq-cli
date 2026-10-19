package com.idq.cli.cli;

import org.jline.utils.AttributedString;
import org.jline.utils.AttributedStyle;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.shell.jline.PromptProvider;

@Configuration
public class ShellConfig {

    /// `TRS+C_S_TRS_PTY+m_Tgt_C_S_TRS_Pty_OnGoing>`; evaluated for every prompt, so latches show immediately.
    @Bean
    PromptProvider idqPromptProvider(LatchState latch) {
        return () -> {
            var context = latch.context();
            return new AttributedString((context.isEmpty() ? "idq (no context)" : context) + "> ",
                    AttributedStyle.DEFAULT.foreground(AttributedStyle.CYAN));
        };
    }
}
