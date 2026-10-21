package com.idq.cli.core.repo;

import java.util.List;

/// Repository fragment for plain `INSERT`s.
///
/// The staging tables carry an assigned key (`PKEY_SRC_OBJECT`, `SRC_KEY`, ...), so Spring Data JDBC's `save` would
/// take every row for an existing one and issue an `UPDATE`. Rows are therefore always inserted with [#insertAll].
public interface InsertRepository<T> {

    <S extends T> List<S> insertAll(List<S> rows);
}
