package com.galaxium.hr.client;

import com.galaxium.hr.model.Employee;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

import java.util.List;

/**
 * MicroProfile REST Client interface for the Python HR Database service.
 *
 * <p>The base URL is resolved from {@code quarkus.rest-client.hr-api.url}
 * which defaults to {@code http://localhost:8081} and can be overridden
 * at runtime via the {@code HR_API_URL} environment variable.
 */
@RegisterRestClient(configKey = "hr-api")
@Path("/employees")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public interface HrApiClient {

    /**
     * Retrieve all employees.
     *
     * @return list of all employees
     */
    @GET
    List<Employee> listAll();

    /**
     * Retrieve a single employee by ID.
     *
     * @param id employee identifier
     * @return the matching employee
     */
    @GET
    @Path("/{id}")
    Employee getById(@PathParam("id") String id);

    /**
     * Create a new employee.
     *
     * @param employee employee data (id may be null)
     * @return the created employee with assigned id
     */
    @POST
    Employee create(Employee employee);

    /**
     * Update an existing employee.
     *
     * @param id       employee identifier
     * @param employee updated employee data
     * @return the updated employee
     */
    @PUT
    @Path("/{id}")
    Employee update(@PathParam("id") String id, Employee employee);

    /**
     * Delete an employee by ID.
     *
     * @param id employee identifier
     */
    @DELETE
    @Path("/{id}")
    void delete(@PathParam("id") String id);
}
