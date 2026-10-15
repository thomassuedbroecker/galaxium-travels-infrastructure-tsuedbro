package com.galaxium.hr.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * DTO mirroring the Python HR API Job schema.
 * All fields are String to match the Python backend's stringly-typed model.
 * {@code id} is nullable — omitted on create requests or dynamically assigned.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public class Job {

    public String id;

    @JsonProperty("job_title")
    public String jobTitle;

    public String description;

    @JsonProperty("required_skills")
    public String requiredSkills;

    @JsonProperty("salary_range")
    public String salaryRange;

    /** Default no-arg constructor required for Jackson deserialization. */
    public Job() {}

    public Job(String id, String jobTitle, String description,
               String requiredSkills, String salaryRange) {
        this.id = id;
        this.jobTitle = jobTitle;
        this.description = description;
        this.requiredSkills = requiredSkills;
        this.salaryRange = salaryRange;
    }
}
