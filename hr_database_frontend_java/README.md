# hr_database_frontend_java — Galaxium Travels HR Portal

A **Quarkus 3 + React 18** frontend for the Galaxium Travels HR Database service.

The application:
- Serves a **React SPA** (built with Vite) as static files
- Exposes a **JAX-RS proxy** at `/api/employees/**` that forwards all CRUD calls to an HR backend
- Runs on **port 8090** (container) / **port 8088** (local)
- Is documented at `/q/swagger-ui` (Swagger UI) and `/q/health` (SmallRye Health)

---

## Architecture

Two backend variants are supported. The frontend image is identical in both cases;
only the `HR_BACKEND_URL` environment variable differs — it is read at runtime, so
switching backends never requires a rebuild.

> The backend host **must not contain underscores**. `java.net.URI.getHost()`
> returns `null` for such hosts and the REST client then silently falls back to
> `localhost:80`. Both compose files therefore give the backend services the
> hyphenated network aliases `hr-database` and `hr-database-backend-java`.

```
Browser → :8090 (Quarkus container)
  ├── GET /           → React SPA (static)
  ├── GET /employees  → React SPA (client-side routing)
  └── /api/employees  → JAX-RS proxy → backend (see below)

Variant A — Python backend (default)
  backend = hr_database container  :8081 (FastAPI, internal network only)

Variant B — Java backend
  backend = hr_database_backend_java container  :8089 (Quarkus, also published on host port 8089)
```

---

## Prerequisites

| Tool        | Minimum version                    |
|-------------|------------------------------------|
| Docker      | 24 (`docker compose` v2 plugin)    |
| _or_ Podman | 4 (`podman-compose`)               |

For local (non-container) development only:

| Tool    | Minimum version                |
|---------|--------------------------------|
| Java    | 21 (OpenJDK / Eclipse Temurin) |
| Maven   | 3.9                            |
| Node.js | 20                             |
| npm     | 10                             |

---

## Quick Start — Container (recommended)

All commands run from the `hr_database_frontend_java/` directory.

### Start

```bash
# Python backend + Java frontend  (default)
./start-hr-app.sh

# Java backend + Java frontend
./start-hr-app.sh --backend java

# Force image rebuild after source changes
./start-hr-app.sh --backend python --build
./start-hr-app.sh --backend java   --build
```

The script builds both images (if not cached), starts them in detached containers,
waits until the frontend health endpoint is up, and prints the access URLs.

### Stop

```bash
./stop-hr-app.sh                  # stops the Python-backend stack
./stop-hr-app.sh --backend java   # stops the Java-backend stack
```

### Access

| URL | Description |
|-----|-------------|
| http://localhost:8090 | HR Portal (React SPA) |
| http://localhost:8090/q/swagger-ui | Swagger UI |
| http://localhost:8090/q/health | Health check |

> Backend ports are **not** bound to the host — they are only reachable inside
> the Docker network to avoid conflicts with any locally running services.

### Logs

```bash
# Python-backend stack
docker compose -f docker-compose.yaml logs -f

# Java-backend stack
docker compose -f docker-compose.java-backend.yaml logs -f
```

---

## Compose Files

| File | Backend | Network |
|------|---------|---------|
| [`docker-compose.yaml`](docker-compose.yaml) | Python FastAPI (`hr_database`, alias `hr-database`, port 8081 internal) | `hr-net` |
| [`docker-compose.java-backend.yaml`](docker-compose.java-backend.yaml) | Quarkus Java (`hr_database_backend_java`, alias `hr-database-backend-java`, port 8089 published on host) | `hr-java-net` |

Both files build the same image, `hr_database_frontend_java:1.0.0`.

---

## Local Development (no containers)

### Quarkus dev mode

Requires the chosen backend running on its default port first.

```bash
# Start the Python backend
cd HR_database
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt pandas
python app.py          # → http://localhost:8081

# In a second terminal — start the Quarkus frontend
cd hr_database_frontend_java
HR_BACKEND_URL=http://localhost:8081 mvn quarkus:dev  # → http://localhost:8088
```

The frontend defaults to `http://localhost:8089`, so the Python backend requires the explicit override above. To use the Java backend:

```bash
cd hr_database_backend_java
mvn quarkus:dev        # → http://localhost:8089

cd hr_database_frontend_java
HR_BACKEND_URL=http://localhost:8089 mvn quarkus:dev
```

### React hot-reload (Vite dev server)

```bash
# Terminal 1: Quarkus proxy (any backend behind it)
cd hr_database_frontend_java
mvn quarkus:dev -Dquarkus.http.port=8088

# Terminal 2: Vite dev server
cd hr_database_frontend_java/src/main/webapp
npm install
npm run dev            # → http://localhost:3000  (proxies /api → :8088)
```

---

## Environment Variables

| Variable     | Default                 | Description                              |
|--------------|-------------------------|------------------------------------------|
| `HR_BACKEND_URL` | `http://localhost:8089` | Base URL of the HR Database backend API (host must not contain underscores) |

### React build variable

| Variable          | Default | Description                                 |
|-------------------|---------|---------------------------------------------|
| `VITE_HR_API_URL` | `/api`  | HR API base URL baked into the React bundle |

Set in `src/main/webapp/.env` or as an environment variable before `npm run build`.

---

## Running Tests

```bash
# Java unit tests
cd hr_database_frontend_java
mvn test

# Contract tests (from repo root, no Docker required)
python3 -m unittest testing.test_local_container_contracts -v
```

---

## Docker Image

### Build manually

```bash
cd hr_database_frontend_java
docker build -t hr_database_frontend_java:1.0.0 .
```

The multi-stage [`Dockerfile`](Dockerfile):
1. **Stage 1 (`builder`)** — `maven:3.9-eclipse-temurin-21`: compiles Java, installs Node via `frontend-maven-plugin`, builds the React Vite bundle, packages the Quarkus fast-jar.
2. **Stage 2 (`runtime`)** — `eclipse-temurin:21-jre-jammy`: minimal JRE, copies only the `quarkus-app/` directory.

### Run standalone (no compose)

```bash
docker run -p 8090:8088 \
  -e HR_BACKEND_URL=http://host.docker.internal:8081 \
  hr_database_frontend_java:1.0.0
```

---

## Project Structure

```
hr_database_frontend_java/
├── Dockerfile                            # Multi-stage Docker build
├── docker-compose.yaml                   # Python backend + Java frontend
├── docker-compose.java-backend.yaml      # Java backend + Java frontend
├── start-hr-app.sh                       # Start the chosen stack (containers)
├── stop-hr-app.sh                        # Stop the chosen stack (containers)
├── pom.xml                               # Maven / Quarkus build
└── src/main/
    ├── java/com/galaxium/hr/
    │   ├── Main.java                     # Quarkus entry point
    │   ├── client/
    │   │   └── HrApiClient.java          # MicroProfile REST Client
    │   ├── model/
    │   │   └── Employee.java             # DTO
    │   └── resource/
    │       └── EmployeeResource.java     # JAX-RS proxy resource
    ├── resources/
    │   ├── application.properties        # Quarkus configuration
    │   └── META-INF/resources/           # Generated React static files
    └── webapp/                           # React + Vite source
        ├── index.html
        ├── package.json
        ├── vite.config.js
        └── src/
            ├── App.jsx
            ├── main.jsx
            ├── components/
            └── pages/
```
