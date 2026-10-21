package com.idq.cli.core.audit;

import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import org.springframework.data.relational.core.mapping.RelationalMappingContext;
import org.springframework.data.relational.core.mapping.RelationalPersistentEntity;
import org.springframework.data.relational.core.mapping.Table;
import org.springframework.stereotype.Component;

/// Table name to `@Table` entity, for every entity in the application (source, target and MDM tables).
///
/// Taken from Spring Data's mapping context, which Spring Boot fills at startup with every `@Table` type of the
/// application package; no classpath scanning of its own.
@Component
public class TableEntities {

    private final Map<String, Class<?>> byTable;

    public TableEntities(RelationalMappingContext mapping) {
        this.byTable = mapping.getPersistentEntities().stream()
                .filter(entity -> entity.isAnnotationPresent(Table.class))
                .collect(Collectors.toUnmodifiableMap(entity -> entity.getTableName().getReference().toUpperCase(),
                        RelationalPersistentEntity::getType, (first, _) -> first));
    }

    public Optional<Class<?>> of(String table) {
        return Optional.ofNullable(byTable.get(table.toUpperCase()));
    }
}
