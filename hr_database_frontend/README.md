# hr_database_frontend — Galaxium Travels HR Portal

A **Quarkus 3 + React 18** frontend for the Galaxium Travels HR Database service.

The application:
- Serves a **React SPA** (built with Vite) as static files
- Exposes a **JAX-RS proxy** at `/api/employees/**` that forwards all CRUD calls to the Python HR Database backend
- Runs on **port 8088**
- Is documented at `/q/swagger-ui` (Swagger UI) and `/q/health` (SmallRye Health)

---

## Architecture

```
Browser → :8088 (Quarkus)
  ├── GET /           → React SPA (static)
  ├── GET /employees  → React SPA (client-side routing)
  └── /api/employees  → JAX-RS proxy → hr_database :8081 (Python FastAPI)
```

---

## Prerequisites

| Tool    | Minimum version |
|---------|----------------|
| Java    | 21 (OpenJDK / Eclipse Temurin) |
| Maven   | 3.9 |
| Node.js | 20 |
| npm     | 10 |
| Docker  | 24 (for container build) |

---

## Local Development

### Option A — one-command startup (recommended)

From the repository root, run:

```bash
bash hr_database_frontend/run-hr-app.sh
```

The script:
- creates `HR_database/.venv` if needed
- installs the Python backend dependencies from `HR_database/requirements.txt`
- installs `pandas` required by `HR_database/app.py`
- starts the backend on **http://localhost:8081**
- packages the Quarkus app and starts the frontend on **http://localhost:8088**
- waits until both services are healthy before printing the URLs

Press `Ctrl+C` to stop both services.

### Option B — Quarkus dev mode (full stack)

Requires the Python HR Database to be running on port 8081.

```bash
cd HR_database
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt pandas
python app.py

# in a second terminal
cd hr_database_frontend
mvn quarkus:dev
```

The Quarkus dev server listens on **http://localhost:8088**.

### Option B — React dev server only (UI hot reload)

For fast UI iteration, run the Vite dev server with the Quarkus proxy in the background.

```bash
# Terminal 1: Quarkus (Java proxy)
cd hr_database_frontend
mvn quarkus:dev -Dquarkus.http.port=8088

# Terminal 2: Vite dev server (React hot reload)
cd hr_database_frontend/src/main/webapp
npm install
npm run dev
# → http://localhost:3000 (proxies /api to Quarkus :8088)
```

---

## Environment Variables

| Variable     | Default                  | Description                              |
|--------------|--------------------------|------------------------------------------|
| `HR_API_URL` | `http://localhost:8081`  | Base URL of the Python HR Database API   |

### React build variable

| Variable          | Default | Description                                      |
|-------------------|---------|--------------------------------------------------|
| `VITE_HR_API_URL` | `/api`  | HR API base URL baked into the React bundle      |

Set in `hr_database_frontend/src/main/webapp/.env` or as an environment variable before `npm run build`.

---

## Running Tests

```bash
# Java unit tests only
cd hr_database_frontend
mvn test

# Contract tests (from repo root, no Docker required)
python3 -m unittest testing.test_local_container_contracts -v
```

---

## Docker Build

### Build image

```bash
cd hr_database_frontend
docker build -t hr_database_frontend:1.0.0 .
```

The multi-stage Dockerfile:
1. **Stage 1 (`builder`)** — `maven:3.9-eclipse-temurin-21`: compiles Java, installs Node via `frontend-maven-plugin`, builds the React Vite bundle, packages the Quarkus fast-jar
2. **Stage 2 (`runtime`)** — `eclipse-temurin:21-jre-jammy`: minimal JRE, copies only the packaged `quarkus-app/` directory

### Run standalone

```bash
docker run -p 8088:8088 \
  -e HR_API_URL=http://host.docker.internal:8081 \
  hr_database_frontend:1.0.0
```

Open **http://localhost:8088**.

---

## Docker Compose

### Standalone (this service only)

```bash
cd hr_database_frontend
docker compose up
```

> **Note:** `HR_API_URL` defaults to `http://localhost:8081`. Update the value in `docker-compose.yaml` if the HR Database runs elsewhere.

### Full stack (all services)

```bash
cd local-container
docker compose up
```

The `hr_database_frontend` service is pre-configured with `HR_API_URL=http://hr_database:8081` using Docker Compose service networking.

---

## API Documentation

| URL                        | Description                  |
|----------------------------|------------------------------|
| http://localhost:8088/q/swagger-ui | Swagger UI for the proxy API |
| http://localhost:8088/q/openapi    | Raw OpenAPI 3.0 spec         |
| http://localhost:8088/q/health     | SmallRye Health (liveness + readiness) |

### Proxy endpoints

| Method | Path                       | Description          |
|--------|----------------------------|----------------------|
| GET    | `/api/employees`           | List all employees   |
| GET    | `/api/employees/{id}`      | Get employee by ID   |
| POST   | `/api/employees`           | Create employee      |
| PUT    | `/api/employees/{id}`      | Update employee      |
| DELETE | `/api/employees/{id}`      | Delete employee      |

---

## Project Structure

```
hr_database_frontend/
├── Dockerfile                        # Multi-stage Docker build
├── docker-compose.yaml               # Standalone compose
├── pom.xml                           # Maven / Quarkus build
├── src/
│   └── main/
│       ├── java/com/galaxium/hr/
│       │   ├── Main.java             # Quarkus entry point
│       │   ├── client/
│       │   │   └── HrApiClient.java  # MicroProfile REST Client
│       │   ├── model/
│       │   │   └── Employee.java     # DTO (mirrors Python schema)
│       │   └── resource/
│       │       └── EmployeeResource.java  # JAX-RS proxy resource
│       ├── resources/
│       │   ├── application.yaml      # Quarkus configuration
│       │   └── META-INF/resources/   # Generated React static files (git-ignored)
│       └── webapp/                   # React + Vite source
│           ├── index.html
│           ├── package.json
│           ├── vite.config.js
│           └── src/
│               ├── App.jsx
│               ├── index.css
│               ├── main.jsx
│               ├── components/
│               │   ├── ErrorMessage.jsx
│               │   ├── LoadingSpinner.jsx
│               │   └── Navbar.jsx
│               ├── pages/
│               │   ├── WelcomePage.jsx
│               │   ├── EmployeeListPage.jsx
│               │   ├── EmployeeDetailPage.jsx
│               │   └── EmployeeFormPage.jsx
│               └── services/
│                   └── hrApiService.js
```
