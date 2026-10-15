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
 * Integration/unit tests for {@link JobResource} verifying all CRUD endpoints.
 */
@QuarkusTest
public class JobResourceTest {

    private static final String TEST_FILE_PATH = "target/test-jobs.md";

    @BeforeEach
    public void setupTestData() throws IOException {
        Path path = Paths.get(TEST_FILE_PATH);
        Path parent = path.getParent();
        if (parent != null && !Files.exists(parent)) {
            Files.createDirectories(parent);
        }

        String initialData = "# Galaxium Travels HR Database\n\n" +
                "## Jobs\n\n" +
                "| id | job_title | description | required_skills | salary_range |\n" +
                "|----|-----------|-------------|-----------------|--------------|\n" +
                "|1|Software Architect|Designs system architecture.|System design, Cloud|$130,000–$170,000|\n" +
                "|2|Product Manager|Defines product roadmap.|Product strategy, Analytics|$110,000–$145,000|\n";

        Files.writeString(path, initialData, StandardCharsets.UTF_8);
    }

    @Test
    public void testGetJobs() {
        given()
                .when().get("/jobs")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("size()", is(2))
                .body("[0].id", is("1"))
                .body("[0].job_title", is("Software Architect"))
                .body("[0].required_skills", is("System design, Cloud"))
                .body("[1].id", is("2"))
                .body("[1].salary_range", is("$110,000–$145,000"));
    }

    @Test
    public void testGetJobById() {
        given()
                .when().get("/jobs/1")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("id", is("1"))
                .body("job_title", is("Software Architect"));
    }

    @Test
    public void testGetJobNotFound() {
        given()
                .when().get("/jobs/999")
                .then()
                .statusCode(404)
                .contentType(ContentType.JSON)
                .body("detail", containsString("Job with ID 999 not found"));
    }

    @Test
    public void testCreateJob() {
        String newJobJson = "{\n" +
                "  \"job_title\": \"Data Engineer\",\n" +
                "  \"description\": \"Builds data pipelines.\",\n" +
                "  \"required_skills\": \"Python, SQL\",\n" +
                "  \"salary_range\": \"$100,000–$130,000\"\n" +
                "}";

        given()
                .contentType(ContentType.JSON)
                .body(newJobJson)
                .when().post("/jobs")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("id", is("3"))
                .body("job_title", is("Data Engineer"));

        // Verify it was written and can be retrieved
        given()
                .when().get("/jobs/3")
                .then()
                .statusCode(200)
                .body("required_skills", is("Python, SQL"));
    }

    @Test
    public void testUpdateJob() {
        String updatedJobJson = "{\n" +
                "  \"job_title\": \"Principal Architect\",\n" +
                "  \"description\": \"Designs system architecture.\",\n" +
                "  \"required_skills\": \"System design, Cloud\",\n" +
                "  \"salary_range\": \"$150,000–$190,000\"\n" +
                "}";

        given()
                .contentType(ContentType.JSON)
                .body(updatedJobJson)
                .when().put("/jobs/1")
                .then()
                .statusCode(200)
                .contentType(ContentType.JSON)
                .body("id", is("1"))
                .body("job_title", is("Principal Architect"));

        given()
                .contentType(ContentType.JSON)
                .body(updatedJobJson)
                .when().put("/jobs/999")
                .then()
                .statusCode(404);
    }

    @Test
    public void testDeleteJob() {
        given()
                .when().delete("/jobs/2")
                .then()
                .statusCode(200)
                .body(containsString("Job deleted successfully"));

        // Verify 404 on get
        given()
                .when().get("/jobs/2")
                .then()
                .statusCode(404);
    }
}
