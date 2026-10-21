package com.idq.cli.core.target;

import com.idq.cli.core.repo.InsertRepository;
import org.springframework.data.repository.Repository;

/// `DQM_ADDRESS`: the address-validation audit is only ever appended.
public interface DqmAddressRepository extends Repository<DqmAddress, DqmAddress.Key>, InsertRepository<DqmAddress> {

    String TABLE = "DQM_ADDRESS";
}
