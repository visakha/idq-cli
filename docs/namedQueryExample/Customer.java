package com.example.demo.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

@Table("CUSTOMER")
public class Customer {
    @Id
    public Long id;
    public String firstName;
    public String email;
}
