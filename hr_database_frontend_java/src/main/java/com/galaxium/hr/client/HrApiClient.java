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
 * MicroProfile REST Client for the HR Database backend.
 *
 * Base URL is set via the QUARKUS_REST_CLIENT_HRBACKEND_URL env var in Compose:
 *   Java backend:   QUARKUS_REST_CLIENT_HRBACKEND_URL=http://hr_database_backend_java:8089
 *   Python backend: QUARKUS_REST_CLIENT_HRBACKEND_URL=http://hr_database:8081
 */
@RegisterRestClient(configKey = "hrbackend")
@Path("/employees")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public interface HrApiClient {

    @GET
    List<Employee> listAll();

    @GET
    @Path("/{id}")
    Employee getById(@PathParam("id") String id);

    @POST
    Employee create(Employee employee);

    @PUT
    @Path("/{id}")
    Employee update(@PathParam("id") String id, Employee employee);

    @DELETE
    @Path("/{id}")
    void delete(@PathParam("id") String id);
}
