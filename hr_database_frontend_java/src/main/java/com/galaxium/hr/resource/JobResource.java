package com.galaxium.hr.resource;

import com.galaxium.hr.client.JobApiClient;
import com.galaxium.hr.model.Job;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

import java.util.List;

/**
 * JAX-RS resource that proxies all CRUD operations for Jobs to the Python HR
 * Database backend via {@link JobApiClient}.
 *
 * <p>All five endpoints mirror the Python FastAPI routes exactly:
 * <ul>
 *   <li>GET  /api/jobs        — list all</li>
 *   <li>GET  /api/jobs/{id}   — get one</li>
 *   <li>POST /api/jobs        — create</li>
 *   <li>PUT  /api/jobs/{id}   — update</li>
 *   <li>DELETE /api/jobs/{id} — delete</li>
 * </ul>
 *
 * <p>HTTP errors from the upstream service are forwarded unchanged so the
 * React client receives the correct status code (404, 500, etc.).
 */
@Path("/api/jobs")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Jobs", description = "CRUD proxy to the HR Database service")
public class JobResource {

    private static final Logger LOG = Logger.getLogger(JobResource.class);

    @Inject
    @RestClient
    JobApiClient jobApiClient;

    /**
     * Re-wraps an upstream error so the original status code and body reach the
     * React client.
     *
     * <p>The REST client raises a {@code ClientWebApplicationException} whose
     * {@code Response} is a <em>client</em> response. Rethrowing it as-is makes
     * Quarkus's default error handler answer 500, which would mask upstream 404s.
     * Reading the body and building a fresh server {@code Response} forwards the
     * status and the FastAPI-style {@code {"detail": ...}} payload unchanged.
     */
    private WebApplicationException forward(WebApplicationException e) {
        Response upstream = e.getResponse();
        if (upstream == null) {
            return new WebApplicationException(Response.Status.BAD_GATEWAY);
        }
        String body = null;
        try {
            body = upstream.readEntity(String.class);
        } catch (Exception ignored) {
            // body not readable — forward the status only
        }
        Response.ResponseBuilder rb = Response.status(upstream.getStatus())
                .type(MediaType.APPLICATION_JSON);
        if (body != null && !body.isBlank()) {
            rb.entity(body);
        }
        return new WebApplicationException(rb.build());
    }

    // -----------------------------------------------------------------------
    // GET /api/jobs
    // -----------------------------------------------------------------------

    @GET
    @Operation(
        operationId = "listJobs",
        summary = "List all jobs",
        description = "Returns the full list of jobs from the HR Database backend."
    )
    @APIResponse(responseCode = "200", description = "List of jobs")
    public List<Job> listAll() {
        try {
            return jobApiClient.listAll();
        } catch (WebApplicationException e) {
            throw forward(e);
        } catch (Exception e) {
            LOG.errorf(e, "Failed to reach HR backend on listAll: %s", e.getMessage());
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // GET /api/jobs/{id}
    // -----------------------------------------------------------------------

    @GET
    @Path("/{id}")
    @Operation(
        operationId = "getJob",
        summary = "Get job by ID",
        description = "Returns a single job identified by the given ID."
    )
    @APIResponse(responseCode = "200", description = "Job found")
    @APIResponse(responseCode = "404", description = "Job not found")
    public Job getById(
            @Parameter(description = "Job ID", required = true)
            @PathParam("id") String id) {
        try {
            return jobApiClient.getById(id);
        } catch (WebApplicationException e) {
            throw forward(e);
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // POST /api/jobs
    // -----------------------------------------------------------------------

    @POST
    @Operation(
        operationId = "createJob",
        summary = "Create a new job",
        description = "Creates a new job record in the HR Database. The id field is auto-assigned."
    )
    @APIResponse(responseCode = "200", description = "Job created")
    public Job create(Job job) {
        try {
            return jobApiClient.create(job);
        } catch (WebApplicationException e) {
            throw forward(e);
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // PUT /api/jobs/{id}
    // -----------------------------------------------------------------------

    @PUT
    @Path("/{id}")
    @Operation(
        operationId = "updateJob",
        summary = "Update an existing job",
        description = "Updates all fields of the job with the given ID."
    )
    @APIResponse(responseCode = "200", description = "Job updated")
    @APIResponse(responseCode = "404", description = "Job not found")
    public Job update(
            @Parameter(description = "Job ID", required = true)
            @PathParam("id") String id,
            Job job) {
        try {
            return jobApiClient.update(id, job);
        } catch (WebApplicationException e) {
            throw forward(e);
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // DELETE /api/jobs/{id}
    // -----------------------------------------------------------------------

    @DELETE
    @Path("/{id}")
    @Operation(
        operationId = "deleteJob",
        summary = "Delete a job",
        description = "Removes the job with the given ID from the HR Database."
    )
    @APIResponse(responseCode = "200", description = "Job deleted")
    @APIResponse(responseCode = "404", description = "Job not found")
    public Response delete(
            @Parameter(description = "Job ID", required = true)
            @PathParam("id") String id) {
        try {
            jobApiClient.delete(id);
            return Response.ok().entity("{\"message\":\"Job deleted successfully\"}").build();
        } catch (WebApplicationException e) {
            throw forward(e);
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }
}
