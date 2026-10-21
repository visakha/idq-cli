package com.idq.cli.core;

import static com.idq.cli.core.EntityBuilder.entity;
import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.source.eci.EciSources.ChildDelta;
import com.idq.cli.source.eci.EciSources.SnCase;
import org.junit.jupiter.api.Test;

class EntityBuilderTest {

    @Test
    void setsComponentsByAccessorAndLeavesTheRestNull() {
        var child = entity(ChildDelta.class)
                .with(ChildDelta::idChild, 9100000001L)
                .with(ChildDelta::firstName, "Mia")
                .with(ChildDelta::birthWtLb, 7)
                .build();
        assertThat(child.idChild()).isEqualTo(9100000001L);
        assertThat(child.firstName()).isEqualTo("Mia");
        assertThat(child.birthWtLb()).isEqualTo(7);
        assertThat(child.lastName()).isNull();
        assertThat(child.dob()).isNull();
    }

    @Test
    void laterValuesReplaceEarlierOnes() {
        var sameCase = entity(SnCase.class).with(SnCase::idCase, 1L).with(SnCase::idCase, 2L).build();
        assertThat(sameCase.idCase()).isEqualTo(2L);
    }

    @Test
    void copiesAndMapsAnExistingRecord() {
        var original = entity(SnCase.class).with(SnCase::idCase, 1L).with(SnCase::idChild, 5L).build();
        var doubled = EntityBuilder.from(original)
                .map((component, value) -> value instanceof Long id ? id * 2 : value)
                .build();
        assertThat(doubled).isEqualTo(new SnCase(2L, null, null, 10L));
        assertThat(original.idCase()).isEqualTo(1L);
    }
}
