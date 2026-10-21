package com.idq.cli.core.repo;

import org.springframework.data.repository.NoRepositoryBean;
import org.springframework.data.repository.Repository;

/// A `C_S_*` target table loaded the IDQ way: emptied ("truncate target table"), then inserted.
///
/// Repositories extend this together with [InsertRepository] (Spring Data only wires the fragments a repository
/// extends directly). `save` is deliberately not exposed, see [InsertRepository].
@NoRepositoryBean
public interface TargetTableRepository<T, ID> extends Repository<T, ID> {

    /// `DELETE FROM <table>`. Callers check the clearable-tables whitelist first.
    void deleteAll();
}
