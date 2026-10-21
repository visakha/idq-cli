package com.idq.cli.core.repo;

import org.springframework.data.repository.NoRepositoryBean;
import org.springframework.data.repository.Repository;

/// A `C_S_*` target table. Loads only insert ([InsertRepository]); nothing is deleted, truncated or dropped, so the
/// IDQ "truncate target table" option is deliberately not reproduced.
///
/// Repositories extend this together with [InsertRepository] (Spring Data only wires the fragments a repository
/// extends directly). `save`, `delete*` and `deleteAll` are deliberately not exposed.
@NoRepositoryBean
public interface TargetTableRepository<T, ID> extends Repository<T, ID> {
}
