package com.idq.cli.core.audit;

import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.data.relational.core.mapping.Table;
import org.springframework.stereotype.Component;
import org.springframework.util.ClassUtils;

/// Table name to `@Table` entity, for every entity in the application (source, target and MDM tables).
@Component
public class TableEntities {

    private final Map<String, Class<?>> byTable;

    public TableEntities() {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(Table.class));
        this.byTable = scanner.findCandidateComponents("com.idq.cli").stream()
                .map(bean -> ClassUtils.resolveClassName(bean.getBeanClassName(), getClass().getClassLoader()))
                .collect(Collectors.toUnmodifiableMap(type -> type.getAnnotation(Table.class).value().toUpperCase(),
                        type -> type, (first, _) -> first));
    }

    public Optional<Class<?>> of(String table) {
        return Optional.ofNullable(byTable.get(table.toUpperCase()));
    }
}
