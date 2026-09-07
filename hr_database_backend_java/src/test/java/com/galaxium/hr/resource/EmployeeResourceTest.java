package com.galaxium.hr.resource;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;

/**
 * Integration/unit tests for {@link EmployeeResource} verifying all CRUD endpoints.
 */
@QuarkusTest
public class EmployeeResourceTest {

    private static final String TEST_FILE_PATH = "target/test-employees.md";

    @BeforeEach
    public void setupTestData() throws IOException {
        Path path = Paths.get(TEST_FILE_PATH);
        Path parent = path.getParent();
        if (parent != null && !Files.exists(parent)) {
            Files.createDirectories(parent);
        }

        String initialData = "# Galaxium Travels HR Database\n\n" +
                "## Employees\n\n" +
                "| id | first_name | last_name | department | position | hire_date | salary |\n" +
                "|----|------------|-----------|------------|----------|-----------|--------|\n" +
                "|1|John|Smith|Engineering|Senior Developer|2023-01-15|85000|\n" +
                "|2|Sarah|Johnson|Marketing|Marketing Manager|2023-04-20|78000|\n";

        Files.writeString(path, initialData, StandardCharsets.UTF_8);
    }

    @Test
    public void testGetEmployees() {
        given()
                .when().get("/employees")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("size()", is(2))
                .body("[0].id", is("1"))
                .body("[0].first_name", is("John"))
                .body("[0].last_name", is("Smith"))
                .body("[1].id", is("2"))
                .body("[1].first_name", is("Sarah"));
    }

    @Test
    public void testGetEmployeeById() {
        given()
                .when().get("/employees/1")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("id", is("1"))
                .body("first_name", is("John"))
                .body("last_name", is("Smith"));
    }

    @Test
    public void testGetEmployeeNotFound() {
        given()
                .when().get("/employees/999")
                .then()
                .statusCode(404)
                .contentType(ContentType.JSON)
                .body("detail", containsString("Employee with ID 999 not found"));
    }

    @Test
    public void testCreateEmployee() {
        String newEmployeeJson = "{\n" +
                "  \"first_name\": \"Michael\",\n" +
                "  \"last_name\": \"Chen\",\n" +
                "  \"department\": \"Sales\",\n" +
                "  \"position\": \"Sales Rep\",\n" +
                "  \"hire_date\": \"2023-08-10\",\n" +
                "  \"salary\": \"65000\"\n" +
                "}";

        given()
                .contentType(ContentType.JSON)
                .body(newEmployeeJson)
                .when().post("/employees")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("id", is("3"))
                .body("first_name", is("Michael"))
                .body("last_name", is("Chen"));

        // Verify it was written and can be retrieved
        given()
                .when().get("/employees/3")
                .then()
                .statusCode(200)
                .body("first_name", is("Michael"));
    }

    @Test
    public void testUpdateEmployee() {
        String updatedEmployeeJson = "{\n" +
                "  \"first_name\": \"John (Updated)\",\n" +
                "  \"last_name\": \"Smith\",\n" +
                "  \"department\": \"Engineering\",\n" +
                "  \"position\": \"Senior Developer\",\n" +
                "  \"hire_date\": \"2023-01-15\",\n" +
                "  \"salary\": \"95000\"\n" +
                "}";

        given()
                .contentType(ContentType.JSON)
                .body(updatedEmployeeJson)
                .when().put("/employees/1")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("id", is("1"))
                .body("first_name", is("John (Updated)"))
                .body("salary", is("95000"));
    }

    @Test
    public void testDeleteEmployee() {
        given()
                .when().delete("/employees/2")
                .then()
                .statusCode(200)
                .body(containsString("Employee deleted successfully"));

        // Verify 404 on get
        given()
                .when().get("/employees/2")
                .then()
                .statusCode(404);
    }
}
