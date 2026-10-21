package com.idq.cli.core.exception;

import com.idq.cli.core.repo.InsertRepository;
import org.springframework.data.repository.Repository;

/// `EXC_STG_BAD_REC_MEMB`: exception rows are only ever appended.
public interface BadRecordRepository extends Repository<BadRecord, BadRecord.Key>, InsertRepository<BadRecord> {

    String TABLE = "EXC_STG_BAD_REC_MEMB";
}
