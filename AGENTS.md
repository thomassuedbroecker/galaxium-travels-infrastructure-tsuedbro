# AGENTS.md

This file provides guidance to agents when working with code in this repository.

**Source of truth.** This file owns the service map, non-obvious patterns, test commands, and code style. Other agent-context files point here instead of repeating it:

| File | Role |
|---|---|
| `AGENTS.md` | Rules, patterns, commands (canonical) |
| [`HANDOFF.md`](./HANDOFF.md) | Current branch state and session log only |
| [`LLMS.txt`](./LLMS.txt) | Self-contained summary for external LLM tools; update it when this file changes |
| `.bob/rules-*/AGENTS.md` | Bob mode-specific additions |

## Project Overview

Python monorepo for a multi-service "Galaxium Travels" booking demo. Seven services:

| Directory | Stack | Port |
|---|---|---|
| `booking_system_rest/` | FastAPI + SQLAlchemy + SQLite | 8082 |
| `booking_system_mcp/` | FastMCP (streamable-HTTP MCP server) | 8084 |
| `galaxium-booking-web-app/` | Flask proxy → REST backend | 8083 |
| `galaxium-booking-web-app-mcp/` | Flask proxy → MCP backend | 8085 |
| `hr_database_backend/` | FastAPI + pandas (reads `data/employees.md`, `data/jobs.md`) | 8081 |
| `hr_database_backend_java/` | Quarkus 3 alternative HR API (same `/employees` + `/jobs` contract; standalone HR stack only) | 8089 |
| `hr_database_frontend_java/` | Quarkus 3 + React 18 HR portal (JAX-RS proxy → Python or Java HR backend) | 8090 (container) / 8088 (local) |

Full stack is orchestrated with `local-container/docker_compose.yaml` and Keycloak on port 8086.

### Labs
[`LABS.md`](./LABS.md) is a logical layer over the runnable setups: lab IDs L01–L10, a learning path, and per-lab start/verify/explore/stop steps. It maps QUICKSTART Options 1–4 (L05, L07, L04, L06), the MCP-only folders (L01–L03), the HR stack (L08) and Code Engine Paths A/B (L09, L10). `local-container/lab.sh` wraps the existing compose files and scripts for L01–L08. **Do not move compose files or the `booking_system_mcp_*` folders to restructure labs**: scripts, contract tests and the external watsonx Orchestrate guide repo reference those paths. When you add or rename a lab, update `LABS.md` and the `LABS`/`lab_title` lists in `lab.sh` together (contract-tested).

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

**WebUI matrix unit tests** (from repo root, no Docker required):
```sh
python3 -m unittest testing.webui_matrix.tests.unit.test_config -v
```

CI (`.github/workflows/tests.yml`) runs the three no-Docker suites (`rest-unit`, `contracts`, `webui-unit`). Run the smallest relevant check first.

## Architecture: Critical Non-Obvious Patterns

### Auth system
Both `booking_system_rest/auth.py` and `booking_system_mcp/auth.py` share the same auth-mode logic:
- `AUTH_ENABLED=true` (legacy) maps to `AUTH_MODE=oauth2`
- `AUTH_MODE=basic` activates HTTP Basic Auth
- `AUTH_MODE=none` (default) skips all auth
- **Conftest always disables auth for unit tests** via `monkeypatch.setenv("AUTH_ENABLED", "false")` — do not set auth env vars in test code.

### Error responses: HTTP 200 with structured error body
`booking_system_rest/app.py` uses `create_error_response()` which returns **HTTP 200** (not 4xx) for business-logic errors (flight not found, seat unavailable, name mismatch). Route `response_model` is `Union[SuccessModel, ErrorResponse]`. Tests must check `response.json()["success"] == False`, not status codes. **Never raise `HTTPException` for business errors.**

The MCP server is different: tools raise exceptions, which FastMCP returns as a successful JSON-RPC result with `"isError": true` and the message text.

### MCP server entry point
`booking_system_mcp/app.py` is a **legacy reference file**, not used. The active entry point is `booking_system_mcp/mcp_server.py`. Dockerfile runs `python mcp_server.py`.

### MCP `/msp` alias
`mcp_server.py` registers `/msp` routes as 307 redirects to `/mcp` for watsonx Orchestrate compatibility — both paths are intentional.

### Database
- SQLite file `booking.db` in service directory (production); in-memory SQLite for tests
- `seed()` is called at **every startup** and **wipes all data first** (`DELETE` before inserting)
- `hr_database_backend` and `hr_database_backend_java` read employees and jobs from Markdown pipe-tables (`data/employees.md`, `data/jobs.md`), not a SQL DB

### Pydantic model naming
In `booking_system_rest/app.py`, SQLAlchemy models are imported with an alias (`from models import Booking as BookingModel`) to avoid collision with Pydantic schema classes named identically (`Booking`, `Flight`, `User`). Follow this pattern when adding new models.

### Compose environment for OIDC
Keycloak listens on 8080 inside the network and is published on host port 8086 (`8086:8080`). In the default `docker_compose.yaml`, `OIDC_ISSUER` is the **container-internal** URL (`http://keycloak:8080/...`). The MCP server includes a hostname-replacement hack to expose the **host-reachable** URL (`localhost:8086`) in OAuth metadata endpoints — this is intentional.

## Code Style

- Python 3.11; `from __future__ import annotations` is used in contract tests but not in service files
- Type hints on all function signatures; `|` union syntax (Python 3.10+), not `Optional`/`Union` where avoidable
- `ConfigDict(from_attributes=True)` for Pydantic v2 ORM models (not `class Config: orm_mode = True`)
- No linter configured (`run_tests.py lint` prints "not configured yet"); follow existing style
- All FastAPI routes include `operation_id`, `summary`, and `description` kwargs — keep these when adding endpoints
- MCP tools (`@mcp.tool()`) have no such kwargs: the function name, docstring, and typed parameters become the tool name, description, and input schema — write clear docstrings

### OAuth flows
- The OAuth **implicit flow is not allowed**. Every Keycloak client has `implicitFlowEnabled: false`, and `verify-keycloak-inspector-client.sh` asserts it.
- Agents and services use `client_credentials` (client `web-app-proxy`); interactive browser login (MCP Inspector) uses `authorization_code`.
- Do not introduce the password grant in new docs or code; some existing verify scripts still use it for the demo traveler.

## Deployment

- IBM Code Engine via bash scripts and `ibmcloud` CLI (not Terraform):
  - Path A (Basic Auth default): `deployment/ibm-code-engine/deploy-stack.sh` (`deploy.env`)
  - Path B (OAuth2 with in-project Keycloak): `deployment/ibm-code-engine/deploy-stack-oauth2.sh` (`deploy.env.oauth2`)
  - Teardown: `teardown-stack.sh` and `teardown-stack-oauth2.sh` (cleans apps/configmaps/secrets without deleting the CE project)
  - Export: `export-deployment.sh [--basic|--oauth2]` writes live links (`deployment-links.env`/`.md`), configmaps and application definitions to git-ignored `generated/exports/<project>-<auth mode>-<timestamp>/` (read-only, no secret values; lives outside `scripts/` because the contract test pins that folder to the eight numbered steps)
  - Root `.ceignore` excludes virtualenvs, `.git`, target folders, and assets to optimize Code Engine source packaging.
- Multiple compose overlays exist for different auth combinations: `docker_compose.basic-auth.yaml`, `docker_compose.basic-auth-vm.yaml`, `docker_compose.mcp-ui-keycloak-basic.yaml`, `docker_compose.vm-oauth.yaml`
- MCP-server-only configurations, one per auth mode, live in `local-container/booking_system_mcp_no_auth/`, `booking_system_mcp_basic_auth/` and `booking_system_mcp_oauth2_no_implicit_flow/`. Each has `start.sh`, `verify.sh` (helpers in `local-container/booking_system_mcp_lib.sh`) and `mcp.env.template`; the overview is `docs/mcp_access_options.md`. The external repo `galaxium-travels-watsonx-orchestrate-mcp-bob-guide` consumes them. In the OAuth folder, Keycloak runs with `--hostname=KEYCLOAK_PUBLIC_BASE_URL`, so the token issuer must match the URL clients use (the LAN IP for watsonx Orchestrate Developer Edition). Realm, clients, and adjustment recipes are documented in `local-container/keycloak/README.md`; the realm import folder can be overridden with `KEYCLOAK_REALM_DIR`. `booking_system_mcp` is the only service provided as MCP.
