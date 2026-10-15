package com.galaxium.hr.resource;

import com.galaxium.hr.model.Job;
import com.galaxium.hr.resource.EmployeeResource.ErrorResponse;
import com.galaxium.hr.service.JobRepository;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;

import java.util.List;
import java.util.Optional;

/**
 * REST Resource implementing the exact same Jobs CRUD endpoints as the Python HR Database backend.
 * Listens on `/jobs` and returns identical error shapes/messages on failures.
 */
@Path("/jobs")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class JobResource {

    @Inject
    JobRepository jobRepository;

    @GET
    @Operation(
        operationId = "getJobs",
        summary = "Get all jobs",
        description = "Returns a list of all jobs."
    )
    public Response getJobs() {
        try {
            List<Job> list = jobRepository.getAll();
            return Response.ok(list).build();
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }

    @GET
    @Path("/{id}")
    @Operation(
        operationId = "getJob",
        summary = "Get a job by ID",
        description = "Returns a single job by its ID."
    )
    public Response getJob(@PathParam("id") String id) {
        try {
            Optional<Job> job = jobRepository.getById(id);
            if (job.isEmpty()) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(new ErrorResponse(String.format(
                                "Job with ID %s not found. The job may have been deleted or the job_id may be incorrect. Please verify the job_id or use the /jobs endpoint to see all available jobs.",
                                id)))
                        .build();
            }
            return Response.ok(job.get()).build();
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }

    @POST
    @Operation(
        operationId = "createJob",
        summary = "Create a new job",
        description = "Creates a new job record and returns it with its new ID."
    )
    public Response createJob(Job job) {
        try {
            Job created = jobRepository.create(job);
            return Response.ok(created).build(); // FastAPI returns HTTP 200 on successful create
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }

    @PUT
    @Path("/{id}")
    @Operation(
        operationId = "updateJob",
        summary = "Update a job",
        description = "Updates an existing job's details."
    )
    public Response updateJob(@PathParam("id") String id, Job job) {
        try {
            Optional<Job> updated = jobRepository.update(id, job);
            if (updated.isEmpty()) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(new ErrorResponse(String.format(
                                "Job with ID %s not found. Cannot update a non-existent job. Please verify the job_id or use the /jobs endpoint to see all available jobs.",
                                id)))
                        .build();
            }
            return Response.ok(updated.get()).build();
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }

    @DELETE
    @Path("/{id}")
    @Operation(
        operationId = "deleteJob",
        summary = "Delete a job",
        description = "Deletes a job record."
    )
    public Response deleteJob(@PathParam("id") String id) {
        try {
            boolean deleted = jobRepository.delete(id);
            if (!deleted) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(new ErrorResponse(String.format(
                                "Job with ID %s not found. Cannot delete a non-existent job. Please verify the job_id or use the /jobs endpoint to see all available jobs.",
                                id)))
                        .build();
            }
            return Response.ok("{\"message\": \"Job deleted successfully\"}").build();
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }
}
