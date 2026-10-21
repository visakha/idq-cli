package com.idq.cli.source.trs.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import java.util.List;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.Repository;

/// `STG_TRS_VALID_MEMBERS` - the members known to be valid. Mapping 001 appends the new ones; every other TRS
/// mapping joins its source rows with this table.
public interface TrsValidMemberRepository extends Repository<TrsSources.ValidMember, String>,
        InsertRepository<TrsSources.ValidMember> {

    String TABLE = "STG_TRS_VALID_MEMBERS";

    /// `lkp_Stg_TRS_Valid_Members` of mapping 001.
    @Query("SELECT PTY_PK FROM STG_TRS_VALID_MEMBERS")
    List<String> fetchValidMemberKeys();
}
