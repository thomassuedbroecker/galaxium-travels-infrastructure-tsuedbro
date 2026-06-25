# HR Frontend – Quarkus + React Plan

## Top-Level Overview

Build a new service `hr_database_frontend/` — a **Quarkus 3 (latest OpenJDK 21)** application that:

1. **Serves a React SPA** (built into `src/main/resources/META-INF/resources/`) as static files
2. **Exposes a Java proxy layer** (`/api/employees/**`) using MicroProfile REST Client and JAX-RS that forwards CRUD calls to the Python HR API (`hr_database` at port 8081)
3. **Implements a full React UI** with Galaxium Travels branding (gold `#f4c768`, deep navy `#081521`, IBM Plex Sans / Space Grotesk fonts) covering:
   - Welcome / landing screen with branding
   - Employee list with search/filter
   - Employee detail view
   - Create employee form
   - Edit employee form
   - Delete confirmation
4. **Containerized** with a multi-stage Dockerfile (Maven build → JVM runtime)
5. **Integrated** into `local-container/docker_compose.yaml` and given its own `docker-compose.yaml`
6. Runs on **port 8088**

The React layer connects to the Quarkus proxy via a build-time env var `REACT_APP_HR_API_URL` (defaults to `/api` so it uses the same origin in the container).

---

## Architecture Diagram (textual)

```
Browser
  └── :8088  →  Quarkus (JAX-RS static file handler + /api proxy)
                    └── MicroProfile REST Client  →  hr_database :8081
```

---

## Sub-Tasks

---

### Sub-Task 1 — Scaffold the Quarkus Project

**Intent:** Establish the Maven project layout, `pom.xml` with Quarkus 3 + OpenJDK 21 BOM, required extensions, and a minimal health-check endpoint so CI can verify the Java skeleton compiles.

**Expected Outcomes:**
- `hr_database_frontend/` directory exists with a valid Maven project
- `mvn quarkus:dev` starts and responds to `GET /q/health`
- `pom.xml` declares Quarkus BOM `3.x.x` (latest stable), Java 21, extensions: `quarkus-resteasy-reactive-jackson`, `quarkus-rest-client-reactive-jackson`, `quarkus-smallrye-openapi`, `quarkus-smallrye-health`, `quarkus-config-yaml`

**Todo List:**
1. Create `hr_database_frontend/` directory
2. Create `pom.xml` using Quarkus 3 BOM (`io.quarkus.platform:quarkus-bom:3.x`), Java 21 source/target, with extensions listed above
3. Create `src/main/resources/application.properties` with:
   - `quarkus.http.port=8088`
   - `quarkus.application.name=hr-database-frontend`
   - `quarkus.smallrye-openapi.info-title=HR Database Frontend`
   - Placeholder `hr.api.url=http://localhost:8081` (overridable via env `HR_API_URL`)
4. Create a minimal `src/main/java/com/galaxium/hr/HealthResource.java` returning `{"status":"UP"}` at `GET /health` (Quarkus SmallRye Health covers this automatically — just confirm it's wired)
5. Create `.gitignore` for Maven targets and Node modules

**Relevant Context:**
- All existing services use `python:3.11-slim`; this is the first Java service — no prior Java pattern to follow
- Quarkus extensions docs: https://quarkus.io/extensions/
- Port 8088 confirmed; do not conflict with existing 8081–8087

**Status:** `[x] done`

---

### Sub-Task 2 — Implement the Quarkus Java Proxy Layer

**Intent:** Build the JAX-RS resource and MicroProfile REST Client that proxy all five CRUD HR endpoints to the Python backend. This is the layer React will call under `/api/employees/**`.

**Expected Outcomes:**
- `GET /api/employees` → proxies `GET http://<HR_API_URL>/employees`
- `GET /api/employees/{id}` → proxies `GET http://<HR_API_URL>/employees/{id}`
- `POST /api/employees` → proxies `POST http://<HR_API_URL>/employees`
- `PUT /api/employees/{id}` → proxies `PUT http://<HR_API_URL>/employees/{id}`
- `DELETE /api/employees/{id}` → proxies `DELETE http://<HR_API_URL>/employees/{id}`
- CORS headers allow `*` (consistent with all other services in this repo)
- OpenAPI spec generated automatically at `/q/openapi`

**Todo List:**
1. Create `Employee.java` DTO record mirroring the Python schema:
   - `id`, `first_name`, `last_name`, `department`, `position`, `hire_date`, `salary` (all `String`, `id` nullable)
2. Create `HrApiClient.java` — MicroProfile `@RegisterRestClient(configKey="hr-api")` interface with all 5 methods
3. Create `EmployeeResource.java` — `@Path("/api/employees")` JAX-RS resource that injects `HrApiClient` and delegates each method; annotate with `@Operation` for OpenAPI
4. Add `quarkus.rest-client.hr-api.url=${HR_API_URL:http://localhost:8081}` to `application.properties`
5. Add `quarkus.http.cors=true` and `quarkus.http.cors.origins=*` to `application.properties`
6. Add error-forwarding: catch `WebApplicationException` from the REST client and re-throw with same status code so React sees correct HTTP errors

**Relevant Context:**
- Python HR API schema: `{id, first_name, last_name, department, position, hire_date, salary}` — all string fields, `id` may be null on create
- HR API has no auth; proxy does not need to forward auth headers
- CORS pattern: existing services set `allow_origins=["*"]` — match this
- `application.properties` key for REST client URL: `quarkus.rest-client.<configKey>.url`

**Status:** `[x] done`

---

### Sub-Task 3 — Scaffold the React Application

**Intent:** Create the React SPA inside `hr_database_frontend/src/main/webapp/` (built output goes to `src/main/resources/META-INF/resources/`). Establish project structure, routing, and the Galaxium branding design system.

**Expected Outcomes:**
- `npm install && npm run build` succeeds and produces `build/` output
- Maven `frontend-maven-plugin` in `pom.xml` runs the React build as part of `mvn package`
- Global CSS variables match Galaxium brand palette
- React Router v6 renders a skeleton app with routes for `/`, `/employees`, `/employees/new`, `/employees/:id/edit`
- IBM Plex Sans and Space Grotesk loaded (via Google Fonts or local)

**Todo List:**
1. Initialise React app in `src/main/webapp/` using `create-react-app` or Vite (prefer Vite for speed); configure `REACT_APP_HR_API_URL` default to `/api`
2. Add `frontend-maven-plugin` to `pom.xml` to run `npm install` and `npm run build` during `mvn package`; configure build output directory to `src/main/resources/META-INF/resources/`
3. Create `src/index.css` with CSS custom properties:
   - `--color-gold: #f4c768`
   - `--color-night: #081521`
   - `--color-ink: #12263a`
   - `--color-ink-soft: #4c6174`
   - `--color-card: rgba(255,255,255,0.92)`
   - `--color-success: #14835d`
   - `--color-danger: #c34747`
   - `--color-accent: #2f7ee7`
4. Add React Router v6 with routes: `/` (Welcome), `/employees` (List), `/employees/new` (Create), `/employees/:id` (Detail), `/employees/:id/edit` (Edit)
5. Create a shared `Navbar` component with Galaxium Travels logo text and navigation links
6. Create `hrApiService.js` — thin wrapper over `fetch` using `REACT_APP_HR_API_URL`; exports `getAll`, `getById`, `create`, `update`, `remove`

**Relevant Context:**
- Quarkus serves static files from `src/main/resources/META-INF/resources/` at the root path
- `frontend-maven-plugin` artifact: `com.github.eirslett:frontend-maven-plugin`
- Existing branding assets in `galaxium-booking-web-app/app/static/` (CSS variables, fonts) — copy approach, not import
- Color palette documented in Sub-Task overview above

**Status:** `[x] done`

---

### Sub-Task 4 — Implement React UI Screens

**Intent:** Build all five React screens (Welcome, Employee List, Employee Detail, Create Form, Edit Form) with Galaxium branding, error handling, loading states, and responsive layout.

**Expected Outcomes:**
- **Welcome screen** (`/`): Galaxium Travels hero with tagline, nav to Employees section; gold accent on dark navy background
- **Employee List** (`/employees`): Table of all employees with Name, Department, Position, Hire Date, Salary; search/filter by name or department; links to detail; Delete button with confirmation; "Add Employee" CTA
- **Employee Detail** (`/employees/:id`): Read-only card view of all fields; Edit and Back buttons
- **Create Form** (`/employees/new`): Form with all fields validated (required); POST on submit; redirect to list on success
- **Edit Form** (`/employees/:id/edit`): Pre-filled form; PUT on submit; redirect to detail on success
- All screens show loading spinners and user-friendly error messages

**Todo List:**
1. Create `WelcomePage.jsx` — hero section with Galaxium Travels heading, subheading ("Human Resources Portal"), gold CTA button to `/employees`; dark navy background with gold accent
2. Create `EmployeeListPage.jsx` — fetch all employees; render table; add search input (client-side filter); Delete button triggers `window.confirm` then calls `hrApiService.remove`; "Add Employee" button routes to `/employees/new`
3. Create `EmployeeDetailPage.jsx` — fetch by id; render labelled fields in a card; "Edit" button routes to edit page; "Back" returns to list
4. Create `EmployeeFormPage.jsx` (shared for create + edit) — controlled form with fields: First Name, Last Name, Department, Position, Hire Date (date input), Salary (number input); validates required fields; on submit calls `create` or `update` depending on presence of `id` param; shows inline validation errors
5. Create shared `LoadingSpinner.jsx` and `ErrorMessage.jsx` components
6. Wire all pages into React Router in `App.jsx`
7. Apply responsive CSS: single-column layout below 768px, two-column form above; use CSS Grid/Flexbox

**Relevant Context:**
- HR API fields: `id`, `first_name`, `last_name`, `department`, `position`, `hire_date`, `salary` — all strings
- `hrApiService.js` from Sub-Task 3 handles all fetch calls
- Existing Flask UI uses card-based layout with `rgba(255,255,255,0.92)` cards on a background — replicate this feel in React CSS modules or plain CSS
- No third-party component library required — plain CSS is consistent with the existing project style

**Status:** `[x] done`

---

### Sub-Task 5 — Dockerfile and Docker Compose Integration

**Intent:** Containerize the Quarkus + React service with a multi-stage Dockerfile and integrate it into both the project's main compose file and a standalone compose file.

**Expected Outcomes:**
- `docker build -t hr_database_frontend:1.0.0 .` in `hr_database_frontend/` succeeds
- Container starts, serves the React SPA at `http://localhost:8088/`, and proxies `/api/employees` to the HR backend
- `hr_database_frontend/docker-compose.yaml` standalone file works with `docker compose up`
- `local-container/docker_compose.yaml` gains a new `hr_database_frontend` service on port `8088:8088` linking to `hr_database`
- `HR_API_URL` env var passed in compose overrides the default

**Todo List:**
1. Create `hr_database_frontend/Dockerfile` — multi-stage:
   - Stage 1 (`builder`): `maven:3.9-eclipse-temurin-21` base; copy `pom.xml` + `src/`; run `mvn package -DskipTests`; the `frontend-maven-plugin` runs the React build inside this stage
   - Stage 2 (runtime): `eclipse-temurin:21-jre-jammy`; copy the fat jar from stage 1; `EXPOSE 8088`; `CMD ["java", "-jar", "quarkus-run.jar"]`
2. Create `hr_database_frontend/docker-compose.yaml`:
   ```yaml
   services:
     hr_database_frontend:
       build: .
       ports: ["8088:8088"]
       environment:
         HR_API_URL: http://localhost:8081
   ```
3. Add service `hr_database_frontend` to `local-container/docker_compose.yaml`:
   - `image: hr_database_frontend:1.0.0`
   - `ports: ["8088:8088"]`
   - `environment: HR_API_URL: http://hr_database:8081`
   - `depends_on: [hr_database]`
4. Update `REACT_APP_HR_API_URL` default to `/api` in the React build so browser calls go to the Quarkus proxy, not directly to port 8081

**Relevant Context:**
- Existing Dockerfiles use slim base images; use `eclipse-temurin:21-jre-jammy` for the JRE stage (official OpenJDK 21)
- Quarkus `quarkus-run.jar` location: `target/quarkus-app/quarkus-run.jar`; requires full `quarkus-app/` directory to be copied, not just the jar
- `local-container/docker_compose.yaml` already has `hr_database` service on port 8081; the new service links to it via service name

**Status:** `[x] done`

---

### Sub-Task 6 — Documentation

**Intent:** Ensure the new service is self-documented and integrated into project-level docs so the contract tests and onboarding README stay accurate.

**Expected Outcomes:**
- `hr_database_frontend/README.md` covers: purpose, prerequisites, local dev commands, environment variables, Docker build, compose usage
- Root-level `README.md` (if one exists) or `local-container/README.md` updated to list port 8088 and the new service
- `testing/test_local_container_contracts.py` updated to assert the new service's port, image name, and env var in the compose file (consistent with existing assertions for other services)

**Todo List:**
1. Write `hr_database_frontend/README.md` with sections: Overview, Prerequisites (Java 21, Node 20, Maven 3.9), Dev Quickstart (`mvn quarkus:dev`), React Dev (`npm start` in `src/main/webapp/`), Environment Variables table, Docker Build, Compose Usage
2. Check root `README.md` for a services table — if present, add a row for `hr_database_frontend` (port 8088, Quarkus + React)
3. Open `testing/test_local_container_contracts.py` and add assertions for:
   - `hr_database_frontend` service present in compose
   - Port mapping `8088:8088`
   - `HR_API_URL` environment variable present
   - `depends_on: hr_database`

**Relevant Context:**
- Contract test file: `testing/test_local_container_contracts.py` — follow exact assertion style used for existing services
- AGENTS.md explicitly states: "Any renaming of env vars, compose files, or shell scripts must be accompanied by updating the corresponding assertions in `testing/test_local_container_contracts.py`"

**Status:** `[x] done`

---

## Key Decisions Recorded

| Decision | Choice | Reason |
|---|---|---|
| Port | 8088 | 8087 reserved for future use |
| API URL strategy | Build-time `REACT_APP_HR_API_URL` | User confirmed; baked into static bundle |
| Architecture | Quarkus static host + JAX-RS proxy | User wants both, extensible for future Java logic |
| Compose integration | Standalone + main compose | User confirmed both |
| Auth | None | HR API has no auth; no new auth layer needed |
| OpenJDK version | 21 (latest LTS) | User requirement: latest OpenJDK |
| React build tool | Vite (inside Maven via frontend-maven-plugin) | Faster than CRA; no ejection needed |
| CSS approach | Plain CSS with CSS custom properties | Consistent with existing Flask UI style |
