package com.galaxium.hr.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * DTO mirroring the Python HR API Employee schema.
 * All fields are String to match the Python backend's stringly-typed model.
 * {@code id} is nullable — omitted on create requests.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public class Employee {

    public String id;

    @JsonProperty("first_name")
    public String firstName;

    @JsonProperty("last_name")
    public String lastName;

    public String department;
    public String position;

    @JsonProperty("hire_date")
    public String hireDate;

    public String salary;

    /** Default no-arg constructor required for Jackson deserialization. */
    public Employee() {}

    public Employee(String id, String firstName, String lastName,
                    String department, String position,
                    String hireDate, String salary) {
        this.id = id;
        this.firstName = firstName;
        this.lastName = lastName;
        this.department = department;
        this.position = position;
        this.hireDate = hireDate;
        this.salary = salary;
    }
}
