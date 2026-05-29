# Architecture Overview

This repository is a runnable comparison of two integration styles for one
travel-booking user journey:

- a browser application calling a REST API
- a browser application calling explicit MCP tools

It is a demonstration architecture, not a production platform. Its purpose is
to make the integration and authentication trade-offs observable without
requiring two different business examples.

## Scope And Boundaries

The two booking paths implement equivalent capabilities, but they are separate
runtimes:

| Path | User-facing application | Backend interface | Local state |
| --- | --- | --- | --- |
| REST | `galaxium-booking-web-app/` | `booking_system_rest/app.py` HTTP endpoints | its own `booking.db` SQLite database |
| MCP | `galaxium-booking-web-app-mcp/` | `booking_system_mcp/mcp_server.py` MCP tools over Streamable HTTP | its own `booking.db` SQLite database |

This means a booking made through the REST UI is not expected to appear in the
MCP UI, or vice versa. Compare the interaction pattern and auth behavior, not
shared transactional state.

`HR_database/` is a standalone supporting example service included in the full
Compose stack. The booking UIs and booking backends do not call it in the
current implementation.

## Container View

```mermaid
flowchart LR
    traveler["Browser user"]
    client["MCP client / agent"]
    keycloak["Keycloak<br/>OAuth option"]

    subgraph rest["REST comparison path"]
        rest_ui["Flask REST UI<br/>:8083"]
        rest_api["FastAPI booking API<br/>:8082"]
        rest_db[("REST SQLite<br/>booking.db")]
        rest_ui -->|"HTTP JSON"| rest_api --> rest_db
    end

    subgraph mcp["MCP comparison path"]
        mcp_ui["Flask MCP UI<br/>:8085"]
        mcp_server["FastMCP server<br/>:8084/mcp"]
        mcp_db[("MCP SQLite<br/>booking.db")]
        mcp_ui -->|"explicit tool calls<br/>Streamable HTTP"| mcp_server --> mcp_db
    end

    traveler --> rest_ui
    traveler --> mcp_ui
    client -->|"tool calls"| mcp_server
    traveler -. "browser login" .-> keycloak
    rest_ui -. "token request" .-> keycloak
    mcp_ui -. "token request" .-> keycloak
    rest_api -. "validate bearer token" .-> keycloak
    mcp_server -. "validate bearer token" .-> keycloak
```

The REST and MCP applications duplicate a small booking domain deliberately:
that keeps the interface comparison visible. It is not a microservice
decomposition or an event-driven synchronization design.

## Responsibilities

| Component | Responsibility | Important constraint |
| --- | --- | --- |
| `booking_system_rest/` | FastAPI endpoints for flights, users, and bookings | HTTP contract; local SQLite state |
| `booking_system_mcp/` | MCP tools for the equivalent booking operations | `mcp_server.py` is active; `app.py` is legacy reference only |
| `galaxium-booking-web-app/` | Web journey backed by REST requests | Sends backend credentials according to mode |
| `galaxium-booking-web-app-mcp/` | Same web journey backed by MCP tool calls | Uses direct Python MCP client; no autonomous agent; Streamable HTTP only |
| `HR_database/` | Separate employee-data demonstration API | Not on either booking request path |
| `local-container/` | Local runtime variants, Keycloak realm, verification scripts | Source of truth for Compose behavior |
| `deployment/ibm-code-engine/` | IBM Code Engine deployment scripts | Deployment package; not live-cloud verified here |
| `testing/` | Contract, smoke, and auth-matrix automation | Source of truth for executed verification scope |

## Request Flows

### REST Booking Flow

1. The browser opens the REST Flask UI.
2. In OAuth mode, the UI authenticates the traveler through Keycloak; in
   Basic Auth mode it uses a guest browser session and configured backend
   credentials.
3. The UI calls the FastAPI booking endpoints with the applicable
   `Authorization` header.
4. The REST backend validates auth, reads or changes its SQLite state, and
   returns JSON.

### MCP Booking Flow

1. The browser opens the MCP Flask UI, or an external MCP client connects to
   `/mcp`.
2. `BookingMcpService` in the MCP UI selects a fixed tool for each UI action.
3. The direct Python MCP client calls the MCP server over Streamable HTTP and
   passes either a bearer token or a Basic Auth header.
4. The MCP tool validates auth, reads or changes its SQLite state, and returns
   structured tool output.

The MCP UI is therefore an explicit application integration example. It does
not use an LLM or dynamic tool planning in the booking path.

## Authentication Variants

| Runtime option | Browser identity | REST backend auth | MCP backend auth | Use case |
| --- | --- | --- | --- | --- |
| Local OAuth | Keycloak traveler login | Bearer token | Bearer token | Compare protected REST and MCP locally |
| VM / LAN OAuth | Keycloak traveler login through public host URL | Bearer token | Bearer token | Reach services from another machine while preserving token issuer URLs |
| Basic Auth | Guest UI session | Shared Basic Auth | Shared Basic Auth | Run without Keycloak |
| Mixed MCP | Keycloak traveler login | Not in this path | Shared Basic Auth | Separate UI identity from MCP backend credentials |

In the LAN OAuth option, public clients and the configured token issuer must
use the LAN-reachable Keycloak URL. Containers can still obtain JWKS over the
internal Docker network. See [local-container/README.md](./local-container/README.md)
for the runtime configuration.

## Deployment View

| Environment | Configuration entry point | Notes |
| --- | --- | --- |
| Local OAuth | `local-container/docker_compose.yaml` | Both comparison paths plus Keycloak and HR API |
| LAN OAuth | `local-container/docker_compose.yaml` plus `docker_compose.vm-oauth.yaml` | Advertises host-reachable OAuth/MCP URLs |
| Local Basic Auth | `local-container/docker_compose.basic-auth.yaml` | Both comparison paths without Keycloak |
| Mixed MCP auth | `local-container/docker_compose.yaml` plus `docker_compose.mcp-ui-keycloak-basic.yaml` | MCP path only in the quickstart command |
| IBM Code Engine | `deployment/ibm-code-engine/` | Scripted deployment package, Basic Auth first |

The SQLite databases and the file-backed HR data are suitable for a local
demonstration. They are not a durable multi-instance data design for
production deployment.

## Key Architecture Decisions

| Decision | Reason | Consequence |
| --- | --- | --- |
| Keep parallel REST and MCP paths | Makes protocol and client-integration differences easy to observe | Domain code and state are duplicated rather than shared |
| Use explicit MCP tool calls from the UI | Shows deterministic application-to-MCP integration | The example does not demonstrate agent planning |
| Support OAuth, Basic Auth, and one mixed path | Exposes authentication boundary choices | Runtime configuration and test combinations are broader |
| Use Compose as the primary local runtime | Provides reproducible service topology and auth dependencies | Host/LAN URL differences must be documented carefully |

## Quality Attributes And Limits

| Attribute | Current approach | Known limit |
| --- | --- | --- |
| Understandability | Small independently runnable services and two visible UI paths | Some implementation is intentionally duplicated |
| Security demonstration | Bearer validation, Basic Auth variants, negative auth tests | Demo credentials are local examples only |
| Portability | Docker Compose and an IBM Code Engine deployment package | Code Engine package has not been executed in a live IBM Cloud account in this workspace |
| Testability | REST tests, runtime smoke tests, auth matrix, deployment contracts | No production load, resilience, or observability validation |
| Data durability | Seeded SQLite for each booking backend | No cross-path consistency or durable production persistence |

## Documentation Map

| Need | Read this |
| --- | --- |
| Run the demo quickly | [QUICKSTART.md](./QUICKSTART.md) |
| Understand architecture and trade-offs | This document |
| Configure local or LAN runtime variants | [local-container/README.md](./local-container/README.md) |
| Check validation scope and commands | [testing/README.md](./testing/README.md) |
| Deploy using IBM Code Engine scripts | [deployment/ibm-code-engine/README.md](./deployment/ibm-code-engine/README.md) |
| Make a contribution | [CONTRIBUTING.md](./CONTRIBUTING.md) |

Editable diagram sources are stored in [`architecture/`](./architecture/).
`ai_generated_documentation/` contains supplemental background material and is
not required to understand or run the current system.
