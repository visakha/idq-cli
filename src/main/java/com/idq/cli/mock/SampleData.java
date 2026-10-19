package com.idq.cli.mock;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.workflow.DatabaseBootstrap;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;
import org.springframework.stereotype.Component;

/// Entry point of `fill-sample-mock-data` / `fill-sample-real-data`: resolves and invokes the function
/// `fill_sample_mock_data_<mapping>` (or `fill_sample_real_data_<mapping>`) of the mapping's source generator.
@Component
public class SampleData {

    public static final String MOCK_PREFIX = "fill_sample_mock_data_";
    public static final String REAL_PREFIX = "fill_sample_real_data_";

    private final List<Object> generators;
    private final ReferenceMockData reference;
    private final DatabaseBootstrap bootstrap;
    private final EtlSettings settings;

    public SampleData(TrsMockData trs, EciMockData eci, ViewMockData views, RealSampleData real,
            ReferenceMockData reference, DatabaseBootstrap bootstrap, EtlSettings settings) {
        this.generators = List.of(trs, eci, views, real);
        this.reference = reference;
        this.bootstrap = bootstrap;
        this.settings = settings;
    }

    public String fillMock(String mapping) {
        if (!settings.mockData()) {
            return "mock_data=false: mock data generation is disabled";
        }
        var function = MOCK_PREFIX + mapping;
        var method = find(function).orElseThrow(() -> new IllegalArgumentException("No function " + function));
        var created = bootstrap.createMissingObjects();
        reference.seed();
        invoke(method);
        return "%s: %d rows per table generated%s".formatted(function, settings.mockRowsPerTable(),
                created.isEmpty() ? "" : " (created missing tables " + created + ")");
    }

    public String fillReal(String mapping) {
        var function = REAL_PREFIX + mapping;
        return find(function).map(method -> {
            invoke(method);
            return function + ": done";
        }).orElse(function + ": not implemented yet (placeholder)");
    }

    private Optional<Method> find(String function) {
        return generators.stream().flatMap(g -> Stream.of(g.getClass().getMethods()))
                .filter(m -> m.getName().equals(function) && m.getParameterCount() == 0).findFirst();
    }

    private void invoke(Method method) {
        var owner = generators.stream().filter(g -> method.getDeclaringClass().isInstance(g)).findFirst()
                .orElseThrow();
        try {
            method.invoke(owner);
        } catch (IllegalAccessException e) {
            throw new IllegalStateException(e);
        } catch (InvocationTargetException e) {
            throw e.getCause() instanceof RuntimeException runtime ? runtime : new IllegalStateException(e.getCause());
        }
    }
}
