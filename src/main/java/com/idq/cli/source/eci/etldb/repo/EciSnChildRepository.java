package com.idq.cli.source.eci.etldb.repo;

import com.idq.cli.core.reference.LookupRows.KeyValue;
import com.idq.cli.source.eci.etldb.models.EciSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_ECI_SN_CHILD` - snapshot of the children.
public interface EciSnChildRepository extends Repository<EciSources.SnChild, Long> {

    /// Child gender by child id, used to pick the relationship type.
    @Query("SELECT TO_CHAR(id_child) AS lookup_key, gender AS lookup_value FROM stg_eci_sn_child")
    List<KeyValue> fetchChildGenders();
}
