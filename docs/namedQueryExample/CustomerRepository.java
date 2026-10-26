package com.example.demo.repository;

import com.example.demo.model.Customer;
import org.springframework.data.repository.CrudRepository;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface CustomerRepository extends CrudRepository<Customer, Long> {

    // 1. Matches "Customer.findByEmail" implicitly based on ClassName.methodName
    Customer findByEmail(@Param("email") String email);

    // 2. Explicitly linked via the 'name' attribute
    @org.springframework.data.jdbc.repository.query.Query(name = "Customer.activeSpecialQuery")
    List<Customer> findActiveCustomers(@Param("firstName") String firstName);
}
