package com.galaxium.hr.resource;

import com.galaxium.hr.client.HrApiClient;
import com.galaxium.hr.model.Employee;
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

import java.util.List;

/**
 * JAX-RS resource that proxies all CRUD operations to the Python HR Database
 * backend via {@link HrApiClient}.
 *
 * <p>All five endpoints mirror the Python FastAPI routes exactly:
 * <ul>
 *   <li>GET  /api/employees        — list all</li>
 *   <li>GET  /api/employees/{id}   — get one</li>
 *   <li>POST /api/employees        — create</li>
 *   <li>PUT  /api/employees/{id}   — update</li>
 *   <li>DELETE /api/employees/{id} — delete</li>
 * </ul>
 *
 * <p>HTTP errors from the upstream service are forwarded unchanged so the
 * React client receives the correct status code (404, 500, etc.).
 */
@Path("/api/employees")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Employees", description = "CRUD proxy to the HR Database service")
public class EmployeeResource {

    @Inject
    @RestClient
    HrApiClient hrApiClient;

    // -----------------------------------------------------------------------
    // GET /api/employees
    // -----------------------------------------------------------------------

    @GET
    @Operation(
        operationId = "listEmployees",
        summary = "List all employees",
        description = "Returns the full list of employees from the HR Database backend."
    )
    @APIResponse(responseCode = "200", description = "List of employees")
    public List<Employee> listAll() {
        try {
            return hrApiClient.listAll();
        } catch (WebApplicationException e) {
            throw e;
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // GET /api/employees/{id}
    // -----------------------------------------------------------------------

    @GET
    @Path("/{id}")
    @Operation(
        operationId = "getEmployee",
        summary = "Get employee by ID",
        description = "Returns a single employee identified by the given ID."
    )
    @APIResponse(responseCode = "200", description = "Employee found")
    @APIResponse(responseCode = "404", description = "Employee not found")
    public Employee getById(
            @Parameter(description = "Employee ID", required = true)
            @PathParam("id") String id) {
        try {
            return hrApiClient.getById(id);
        } catch (WebApplicationException e) {
            throw e;
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // POST /api/employees
    // -----------------------------------------------------------------------

    @POST
    @Operation(
        operationId = "createEmployee",
        summary = "Create a new employee",
        description = "Creates a new employee record in the HR Database. The id field is auto-assigned."
    )
    @APIResponse(responseCode = "200", description = "Employee created")
    public Employee create(Employee employee) {
        try {
            return hrApiClient.create(employee);
        } catch (WebApplicationException e) {
            throw e;
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // PUT /api/employees/{id}
    // -----------------------------------------------------------------------

    @PUT
    @Path("/{id}")
    @Operation(
        operationId = "updateEmployee",
        summary = "Update an existing employee",
        description = "Updates all fields of the employee with the given ID."
    )
    @APIResponse(responseCode = "200", description = "Employee updated")
    @APIResponse(responseCode = "404", description = "Employee not found")
    public Employee update(
            @Parameter(description = "Employee ID", required = true)
            @PathParam("id") String id,
            Employee employee) {
        try {
            return hrApiClient.update(id, employee);
        } catch (WebApplicationException e) {
            throw e;
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }

    // -----------------------------------------------------------------------
    // DELETE /api/employees/{id}
    // -----------------------------------------------------------------------

    @DELETE
    @Path("/{id}")
    @Operation(
        operationId = "deleteEmployee",
        summary = "Delete an employee",
        description = "Removes the employee with the given ID from the HR Database."
    )
    @APIResponse(responseCode = "200", description = "Employee deleted")
    @APIResponse(responseCode = "404", description = "Employee not found")
    public Response delete(
            @Parameter(description = "Employee ID", required = true)
            @PathParam("id") String id) {
        try {
            hrApiClient.delete(id);
            return Response.ok().entity("{\"message\":\"Employee deleted successfully\"}").build();
        } catch (WebApplicationException e) {
            throw e;
        } catch (Exception e) {
            throw new WebApplicationException("Failed to reach HR backend: " + e.getMessage(),
                    Response.Status.BAD_GATEWAY);
        }
    }
}
