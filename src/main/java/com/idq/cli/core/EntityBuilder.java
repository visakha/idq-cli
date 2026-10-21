package com.idq.cli.core;

import java.io.Serializable;
import java.lang.invoke.SerializedLambda;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.RecordComponent;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BiFunction;
import java.util.function.Function;

/// Fluent, typed construction of wide entity records (source tables have up to 62 columns), where a positional
/// constructor full of `null`s would be unreadable. Components are named by their accessor, so values are checked
/// by the compiler and there are no column-name strings:
///
/// ```java
/// entity(EciSources.ChildDelta.class)
///         .with(ChildDelta::idChild, id)
///         .with(ChildDelta::firstName, "Mia")
///         .build();
/// ```
///
/// Components that are not set are `null`.
public final class EntityBuilder<R extends Record> {

    /// An accessor method reference such as `ChildDelta::firstName`.
    @FunctionalInterface
    public interface Component<R, V> extends Function<R, V>, Serializable {}

    private static final Map<Class<?>, String> NAMES = new ConcurrentHashMap<>();

    private final Class<R> type;
    private final RecordComponent[] components;
    private final Object[] values;

    private EntityBuilder(Class<R> type, Object[] values) {
        this.type = type;
        this.components = type.getRecordComponents();
        this.values = values;
    }

    public static <R extends Record> EntityBuilder<R> entity(Class<R> type) {
        return new EntityBuilder<>(type, new Object[type.getRecordComponents().length]);
    }

    /// Starts from the values of an existing record.
    @SuppressWarnings("unchecked")
    public static <R extends Record> EntityBuilder<R> from(R record) {
        var type = (Class<R>) record.getClass();
        return new EntityBuilder<>(type, Arrays.stream(type.getRecordComponents()).map(c -> read(c, record))
                .toArray());
    }

    public <V> EntityBuilder<R> with(Component<R, V> component, V value) {
        values[index(name(component))] = value;
        return this;
    }

    /// Replaces every component value by `change(component, value)`.
    public EntityBuilder<R> map(BiFunction<RecordComponent, Object, Object> change) {
        for (int i = 0; i < components.length; i++) {
            values[i] = change.apply(components[i], values[i]);
        }
        return this;
    }

    public R build() {
        try {
            var parameterTypes = Arrays.stream(components).map(RecordComponent::getType).toArray(Class<?>[]::new);
            return type.getDeclaredConstructor(parameterTypes).newInstance(values.clone());
        } catch (InvocationTargetException e) {
            throw e.getCause() instanceof RuntimeException runtime ? runtime : new IllegalStateException(e);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Cannot build " + type.getName(), e);
        }
    }

    private int index(String name) {
        for (int i = 0; i < components.length; i++) {
            if (components[i].getName().equals(name)) {
                return i;
            }
        }
        throw new IllegalArgumentException(name + " is not a component of " + type.getName());
    }

    /// The accessor's method name, read once per method reference from its serialized form.
    static String name(Component<?, ?> component) {
        return NAMES.computeIfAbsent(component.getClass(), lambda -> {
            try {
                var writeReplace = lambda.getDeclaredMethod("writeReplace");
                writeReplace.setAccessible(true);
                return ((SerializedLambda) writeReplace.invoke(component)).getImplMethodName();
            } catch (ReflectiveOperationException e) {
                throw new IllegalArgumentException("Pass an accessor method reference such as ChildDelta::firstName", e);
            }
        });
    }

    private static Object read(RecordComponent component, Record record) {
        try {
            return component.getAccessor().invoke(record);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
