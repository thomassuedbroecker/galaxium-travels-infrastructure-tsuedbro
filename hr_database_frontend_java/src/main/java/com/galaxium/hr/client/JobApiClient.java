package com.galaxium.hr.client;

import com.galaxium.hr.model.Job;
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
 * MicroProfile REST Client for the HR Database backend Jobs resource.
 *
 * Base URL is set via the QUARKUS_REST_CLIENT_HRBACKEND_URL env var in Compose:
 *   Java backend:   QUARKUS_REST_CLIENT_HRBACKEND_URL=http://hr_database_backend_java:8089
 *   Python backend: QUARKUS_REST_CLIENT_HRBACKEND_URL=http://hr_database:8081
 *
 * Reuses the {@code hrbackend} configKey, so no application.properties change is needed.
 */
@RegisterRestClient(configKey = "hrbackend")
@Path("/jobs")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public interface JobApiClient {

    @GET
    List<Job> listAll();

    @GET
    @Path("/{id}")
    Job getById(@PathParam("id") String id);

    @POST
    Job create(Job job);

    @PUT
    @Path("/{id}")
    Job update(@PathParam("id") String id, Job job);

    @DELETE
    @Path("/{id}")
    void delete(@PathParam("id") String id);
}
