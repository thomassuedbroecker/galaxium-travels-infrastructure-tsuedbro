package com.galaxium.hr.resource;

import com.galaxium.hr.model.Employee;
import com.galaxium.hr.service.EmployeeRepository;
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
 * REST Resource implementing the exact same CRUD endpoints as the Python HR Database backend.
 * Listens on `/employees` and returns identical error shapes/messages on failures.
 */
@Path("/employees")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class EmployeeResource {

    @Inject
    EmployeeRepository employeeRepository;

    /**
     * DTO for matching the detail error response body structure of FastAPI.
     */
    public static class ErrorResponse {
        public String detail;
        public ErrorResponse() {}
        public ErrorResponse(String detail) {
            this.detail = detail;
        }
    }

    @GET
    @Operation(
        operationId = "getEmployees",
        summary = "Get all employees",
        description = "Returns a list of all employees."
    )
    public Response getEmployees() {
        try {
            List<Employee> list = employeeRepository.getAll();
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
        operationId = "getEmployee",
        summary = "Get an employee by ID",
        description = "Returns a single employee by their ID."
    )
    public Response getEmployee(@PathParam("id") String id) {
        try {
            Optional<Employee> emp = employeeRepository.getById(id);
            if (emp.isEmpty()) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(new ErrorResponse(String.format(
                                "Employee with ID %s not found. The employee may have been deleted or the employee_id may be incorrect. Please verify the employee_id or use the /employees endpoint to see all available employees.",
                                id)))
                        .build();
            }
            return Response.ok(emp.get()).build();
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }

    @POST
    @Operation(
        operationId = "createEmployee",
        summary = "Create a new employee",
        description = "Creates a new employee record and returns it with its new ID."
    )
    public Response createEmployee(Employee employee) {
        try {
            Employee created = employeeRepository.create(employee);
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
        operationId = "updateEmployee",
        summary = "Update an employee",
        description = "Updates an existing employee's details."
    )
    public Response updateEmployee(@PathParam("id") String id, Employee employee) {
        try {
            Optional<Employee> updated = employeeRepository.update(id, employee);
            if (updated.isEmpty()) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(new ErrorResponse(String.format(
                                "Employee with ID %s not found. Cannot update a non-existent employee. Please verify the employee_id or use the /employees endpoint to see all available employees.",
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
        operationId = "deleteEmployee",
        summary = "Delete an employee",
        description = "Deletes an employee record."
    )
    public Response deleteEmployee(@PathParam("id") String id) {
        try {
            boolean deleted = employeeRepository.delete(id);
            if (!deleted) {
                return Response.status(Response.Status.NOT_FOUND)
                        .entity(new ErrorResponse(String.format(
                                "Employee with ID %s not found. Cannot delete a non-existent employee. Please verify the employee_id or use the /employees endpoint to see all available employees.",
                                id)))
                        .build();
            }
            return Response.ok("{\"message\": \"Employee deleted successfully\"}").build();
        } catch (Exception e) {
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity(new ErrorResponse(e.getMessage()))
                    .build();
        }
    }
}
