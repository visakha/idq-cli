package com.idq.cli.core.repo;

import java.util.List;
import org.springframework.data.jdbc.core.JdbcAggregateTemplate;

/// Implementation of the [InsertRepository] fragment, shared by every repository that extends it.
public class InsertRepositoryImpl<T> implements InsertRepository<T> {

    private final JdbcAggregateTemplate aggregates;

    public InsertRepositoryImpl(JdbcAggregateTemplate aggregates) {
        this.aggregates = aggregates;
    }

    @Override
    public <S extends T> List<S> insertAll(List<S> rows) {
        return aggregates.insertAll(rows);
    }
}
