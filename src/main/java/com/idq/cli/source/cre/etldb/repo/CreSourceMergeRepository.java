package com.idq.cli.source.cre.etldb.repo;

import com.idq.cli.core.repo.InsertRepository;
import com.idq.cli.source.cre.etldb.models.CreSources;
import org.springframework.data.repository.Repository;

/// `CRE_SRC_MRG` - case moves for MDM to merge. The mapping only appends to it.
public interface CreSourceMergeRepository extends Repository<CreSources.SourceMerge, String>,
        InsertRepository<CreSources.SourceMerge> {

    String TABLE = "CRE_SRC_MRG";
}
