# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project Overview

Python monorepo for a multi-service "Galaxium Travels" booking demo. Six services:

| Directory | Stack | Port |
|---|---|---|
| `booking_system_rest/` | FastAPI + SQLAlchemy + SQLite | 8082 |
| `booking_system_mcp/` | FastMCP (streamable-HTTP MCP server) | 8084 |
| `galaxium-booking-web-app/` | Flask proxy → REST backend | 8083 |
| `galaxium-booking-web-app-mcp/` | Flask proxy → MCP backend | 8085 |
| `HR_database/` | FastAPI + pandas (reads `data/employees.md`) | 8081 |
| `hr_database_frontend/` | Quarkus 3 + React 18 HR portal (JAX-RS proxy → `HR_database`) | 8088 |

Full stack is orchestrated with `local-container/docker_compose.yaml` and Keycloak on port 8086.

## Test Commands

**REST API unit tests** (run from `booking_system_rest/`):
```sh
python3 -m pytest tests -q                        # fast
python3 -m pytest tests -v                        # verbose
python3 -m pytest tests/test_booking_system.py -v # single file
python3 -m pytest tests -k "test_name" -v         # single test by name
python -m pytest tests --cov=app --cov=models --cov=db --cov-report=term-missing  # with coverage
```
`pytest.ini` auto-applies coverage; omit `--cov` only if you want to skip it.

**Contract / doc-consistency tests** (from repo root, no Docker required):
```sh
python3 -m unittest testing.test_local_container_contracts -v
python3 -m unittest testing.test_code_engine_deployment_contracts -v
```

**Automation suite** (requires Docker):
```sh
bash testing/automation/run-rest-api-tests.sh       # REST unit tests inside container
bash testing/automation/run-local-container-contract-tests.sh
bash testing/automation/run-mcp-integration-tests.sh
bash testing/automation/run-all-tests.sh            # everything
```

## Architecture: Critical Non-Obvious Patterns

### Auth system
Both `booking_system_rest/auth.py` and `booking_system_mcp/auth.py` share the same auth-mode logic:
- `AUTH_ENABLED=true` (legacy) maps to `AUTH_MODE=oauth2`
- `AUTH_MODE=basic` activates HTTP Basic Auth
- `AUTH_MODE=none` (default) skips all auth
- **Conftest always disables auth for unit tests** via `monkeypatch.setenv("AUTH_ENABLED", "false")` — do not set auth env vars in test code.

### Error responses: HTTP 200 with structured error body
`booking_system_rest/app.py` uses `create_error_response()` which returns **HTTP 200** (not 4xx) for business-logic errors (flight not found, seat unavailable, name mismatch). Route `response_model` is `Union[SuccessModel, ErrorResponse]`. Tests must check `response.json()["success"] == False`, not status codes.

### MCP server entry point
`booking_system_mcp/app.py` is a **legacy reference file**, not used. The active entry point is `booking_system_mcp/mcp_server.py`. Dockerfile runs `python mcp_server.py`.

### MCP `/msp` alias
`mcp_server.py` registers `/msp` routes as 307 redirects to `/mcp` for Watson Discovery compatibility — both paths are intentional.

### Database
- SQLite file `booking.db` in service directory (production); in-memory SQLite for tests
- `seed()` is called at **every startup** and **wipes all data first** (`DELETE` before inserting)
- `HR_database` reads employees from a Markdown pipe-table (`data/employees.md`), not a SQL DB

### Pydantic model naming
In `booking_system_rest/app.py`, SQLAlchemy models are imported with an alias (`from models import Booking as BookingModel`) to avoid collision with Pydantic schema classes named identically (`Booking`, `Flight`, `User`). Follow this pattern when adding new models.

### Compose environment for OIDC
In the default `docker_compose.yaml`, `OIDC_ISSUER` is the **container-internal** URL (`http://keycloak:8080/...`). The MCP server includes a hostname-replacement hack to expose the **host-reachable** URL (`localhost:8086`) in OAuth metadata endpoints — this is intentional.

## Code Style

- Python 3.11; `from __future__ import annotations` is used in contract tests but not in service files
- Type hints on all function signatures; `|` union syntax (Python 3.10+), not `Optional`/`Union` where avoidable
- `ConfigDict(from_attributes=True)` for Pydantic v2 ORM models (not `class Config: orm_mode = True`)
- No linter configured (`run_tests.py lint` prints "not configured yet"); follow existing style
- All routes include `operation_id`, `summary`, and `description` kwargs — keep these when adding endpoints

## Deployment

- IBM Code Engine via `deployment/ibm-code-engine/deploy-stack.sh` (bash + ibmcloud CLI, not Terraform)
- Default Code Engine auth mode is `basic` (see `deploy.env.template`)
- Multiple compose overlays exist for different auth combinations: `docker_compose.basic-auth.yaml`, `docker_compose.basic-auth-vm.yaml`, `docker_compose.mcp-ui-keycloak-basic.yaml`, `docker_compose.vm-oauth.yaml`
