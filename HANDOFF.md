# HANDOFF.md — Galaxium Travels Infrastructure

This file is the shared context document for AI-assisted development across
multiple agentic IDEs (Bob / Cursor, Claude Code, Codex, and similar tools).
Keep it up to date whenever you complete a significant task so the next
agent or session starts from accurate state.

---

## Project in one sentence

Python monorepo that demonstrates REST vs MCP integration for a travel-booking
domain — same business flow, two separate runtimes, swappable auth modes.

---

## Repo map (read this before touching anything)

| Directory | Stack | Port | Entry point |
|---|---|---|---|
| `booking_system_rest/` | FastAPI + SQLAlchemy + SQLite | 8082 | `app.py` |
| `booking_system_mcp/` | FastMCP Streamable HTTP | 8084 | `mcp_server.py` ← active |
| `galaxium-booking-web-app/` | Flask proxy → REST | 8083 | `app/app.py` |
| `galaxium-booking-web-app-mcp/` | Flask proxy → MCP tools | 8085 | `app/app.py` |
| `HR_database/` | FastAPI + pandas + Markdown | 8081 | `app.py` |
| `local-container/` | Docker Compose variants + scripts | — | `docker_compose.yaml` |
| `deployment/ibm-code-engine/` | Bash + ibmcloud CLI deploy | — | `deploy-stack.sh` |
| `testing/` | Pytest, contract tests, smoke scripts | — | `README.md` |

> `booking_system_mcp/app.py` is a **legacy reference file** — the Dockerfile
> runs `mcp_server.py`. Never edit `app.py` thinking it will affect runtime.

---

## Current branch and state

| Field | Value |
|---|---|
| Branch | `main` |
| Last known clean commit | `4291e19` — docs: improve developer and AI engineer navigation |
| Uncommitted changes | none at last handoff |

Update this section at the end of every session.

---

## Non-obvious patterns every agent must know

### 1 — Business errors return HTTP 200
`booking_system_rest/app.py` uses `create_error_response()` which returns
`JSONResponse(status_code=200, ...)` for business-logic errors (flight not
found, seat unavailable, name mismatch). **Never raise `HTTPException` for
business errors.** Tests check `response.json()["success"] == False`, not
status codes.

### 2 — Auth modes are shared across both services
Both `booking_system_rest/auth.py` and `booking_system_mcp/auth.py` read the
same env vars:

| `AUTH_MODE` | Behaviour |
|---|---|
| `none` (default) | No auth — dev only |
| `basic` | HTTP Basic Auth; no Keycloak needed |
| `oauth2` | Bearer token via Keycloak JWT |

`AUTH_ENABLED=true` is a legacy alias for `AUTH_MODE=oauth2`.
Unit-test `conftest.py` always monkeypatches `AUTH_ENABLED=false` — do not
set auth env vars in individual test code.

### 3 — Database is wiped on every startup
`seed()` runs at startup in both booking services and issues `DELETE` before
inserting seed rows. Do not rely on DB state persisting between restarts.
Tests use in-memory SQLite.

### 4 — Pydantic model alias pattern
`booking_system_rest/app.py` imports SQLAlchemy models as
`from models import Booking as BookingModel` to avoid collision with
identically-named Pydantic schema classes. Follow this in all new code.

### 5 — MCP `/msp` alias is intentional
`mcp_server.py` registers `/msp` as a 307 redirect to `/mcp` for Watson
Discovery compatibility. Do not remove it.

### 6 — Keycloak dual-URL pattern
`OIDC_ISSUER` inside containers uses `http://keycloak:8080/...`.
The MCP server hostname-replacement hack rewrites this to `localhost:8086` in
OAuth metadata responses for host-side clients. Both URLs point to the same
instance; the mapping is `8086:8080`.

### 7 — Route metadata is required
Every FastAPI and MCP route must include `operation_id`, `summary`, and
`description` kwargs. These are consumed by Watson Orchestrate and MCP
Inspector.

### 8 — Pydantic v2 ORM config
Use `ConfigDict(from_attributes=True)`. Do **not** use the v1 pattern
`class Config: orm_mode = True` in new code (the MCP server still has it;
do not copy it).

---

## Test commands (run these to validate work)

```sh
# Fast — REST unit tests; run from booking_system_rest/
python3 -m pytest tests -q

# Contract tests — no Docker required; run from repo root
python3 -m unittest testing.test_local_container_contracts \
                    testing.test_code_engine_deployment_contracts -v

# Full automated suite — requires Docker
bash testing/automation/run-all-tests.sh

# Single test
python3 -m pytest tests/test_booking_system.py::TestClassName::test_method_name -v
```

> Always run the smallest relevant check first. See `testing/README.md` for
> the full scope.

---

## Auth mode quickstart matrix

| Option | Compose file(s) | Env file | Identity |
|---|---|---|---|
| 1 — Local OAuth | `local-container/docker_compose.yaml` | none | Keycloak traveler login |
| 2 — VM/LAN OAuth | `docker_compose.yaml` + `docker_compose.vm-oauth.yaml` | `local-container/vm-oauth.env` | Keycloak over LAN |
| 3 — Basic Auth | `local-container/docker_compose.basic-auth.yaml` | `local-container/basic-auth.env` | Shared Basic Auth |
| 4 — Mixed | `docker_compose.yaml` + `docker_compose.mcp-ui-keycloak-basic.yaml` | `local-container/basic-auth.env` | Keycloak browser + MCP Basic Auth |

Demo credentials (local only — not for production):

| Account | Username | Password |
|---|---|---|
| Keycloak admin | `admin` | `admin` |
| Traveler | `demo-user` | `demo-user-password` |
| Basic Auth | `demo-basic-user` | `demo-basic-password` |

---

## Key reference documents

| Need | File |
|---|---|
| Decision-tree navigation hub | [`NAVIGATOR.md`](./NAVIGATOR.md) |
| Step-by-step run commands | [`QUICKSTART.md`](./QUICKSTART.md) |
| Architecture decisions and component map | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| Agent and LLM coding rules | [`AGENTS.md`](./AGENTS.md) |
| MCP endpoints, tools, auth for AI engineers | [`docs/AI_ENGINEER_GUIDE.md`](./docs/AI_ENGINEER_GUIDE.md) |
| Compose variants and verification scripts | [`local-container/README.md`](./local-container/README.md) |
| Test scope and evidence | [`testing/README.md`](./testing/README.md) |
| Machine-readable repo summary for LLM tools | [`LLMS.txt`](./LLMS.txt) |

---

## Agentic IDE — per-tool notes

### Bob (Cursor)
- Project rules are loaded from `AGENTS.md` automatically.
- `LLMS.txt` is registered in `NAVIGATOR.md` as the machine-readable summary.
- Use `apply_diff` / `search_and_replace` for surgical edits; avoid full
  rewrites of large files.

### Claude Code
- Read `AGENTS.md` at session start — it encodes the non-obvious patterns.
- Run `python3 -m pytest tests -q` from `booking_system_rest/` before and
  after any change to the REST service.
- Respect the HTTP-200 error contract; do not introduce `HTTPException` for
  business errors.

### Codex (or any OpenAI-based agent)
- This file (`HANDOFF.md`) plus `AGENTS.md` are the minimum required context.
- Provide both files in the system prompt or `context_files` when starting a
  new session.
- Follow the Pydantic v2 `ConfigDict(from_attributes=True)` pattern for any
  ORM model you add.

---

## How to update this file

At the end of a work session update the two fields below, then commit:

```
## Session log
```

| Date | Agent / IDE | Branch | What changed | Next open task |
|---|---|---|---|---|
| 2026-06-20 | Bob (Cursor) | main | Created HANDOFF.md | — |

---

## Session log

| Date | Agent / IDE | Branch | What changed | Next open task |
|---|---|---|---|---|
| 2026-06-20 | Bob (Cursor) | main | Initial HANDOFF.md created | — |
