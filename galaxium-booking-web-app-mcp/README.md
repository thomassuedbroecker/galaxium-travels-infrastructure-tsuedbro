# Galaxium Booking Web App MCP

| | |
| --- | --- |
| **Port** | `8085` |
| **Entry point** | `app/app.py` |
| **Auth config** | `BACKEND_AUTH_MODE=none\|basic\|oauth2` · `FRONTEND_AUTH_REQUIRED=true\|false` |
| **Local run** | `cd app && python app.py` |
| **Test command** | n/a (use compose smoke scripts) |
| **Compose service** | `web_app_mcp` |

Flask UI that preserves the existing traveler experience but invokes booking tools through a direct Python MCP client integration.

The existing REST-backed app in `../galaxium-booking-web-app/` remains unchanged.

## Run Locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r app/requirements.txt
source .env-template
cd app
python app.py
```

Default URL: `http://localhost:8085`

## Security Model

- `BACKEND_AUTH_MODE=oauth2` and `FRONTEND_AUTH_REQUIRED=true`
  - Traveler login mode.
  - MCP tool calls reuse the authenticated traveler bearer token.

- `BACKEND_AUTH_MODE=basic` and `FRONTEND_AUTH_REQUIRED=true`
  - Traveler login with Keycloak, MCP backend with Basic Auth.
  - The UI keeps the traveler browser session in Keycloak, but MCP tool calls use the shared Basic Auth header.

- `BACKEND_AUTH_MODE=oauth2` and `FRONTEND_AUTH_REQUIRED=false`
  - Service-to-service OAuth mode.
  - The UI stores a guest traveler profile in the browser session.

- `BACKEND_AUTH_MODE=basic` and `FRONTEND_AUTH_REQUIRED=false`
  - Shared Basic Auth mode.
  - The UI stores a guest traveler profile in the browser session and sends the shared Basic Auth header to the MCP server.

- `BACKEND_AUTH_MODE=none` and `FRONTEND_AUTH_REQUIRED=false`
  - Local unsecured mode.
  - The UI stores a guest traveler profile in the browser session and calls the MCP server without an `Authorization` header.

The direct Python MCP client always stays on `Streamable HTTP`. Do not switch this app to another MCP transport.

## Implementation Overview

This application is the MCP-backed variant of the booking UI. It keeps the same traveler-facing web experience, but replaces the previous booking backend integration with direct MCP tool calls from the application service layer.

### Main Components

- `app/app.py`
  - Runs the Flask web application.
  - Handles routes, login redirects, session state, and authenticated traveler context.
  - Calls the booking service layer for booking operations instead of talking to a REST booking backend.
- `app/booking_mcp_service.py`
  - Implements the explicit MCP integration required by this application.
  - Opens the Python MCP client connection to the booking MCP server over `Streamable HTTP`.
  - Passes the configured `Authorization` header to the MCP server on every tool call.
  - Calls fixed MCP tools directly. No agent, planner, or autonomous tool selection is used.

### Why The Service Layer Exists

`booking_mcp_service.py` is required because this application must invoke MCP tools explicitly from the application service layer. That service centralizes:

- MCP client session setup and cleanup
- OAuth bearer token forwarding
- explicit tool-to-method mapping
- normalization of MCP SDK response payloads
- translation of MCP/tool failures into stable application errors

Without this layer, the Flask routes would need to duplicate MCP transport logic, token handling, and error handling.

### MCP Tools Used

The service layer calls these booking backend tools directly:

- `list_flights`
- `get_user_id`
- `register_user`
- `book_flight`
- `get_bookings`
- `cancel_booking`

### Request Flow

1. The traveler signs in through Keycloak.
2. Flask stores the authenticated session and access token.
3. A UI action calls a Flask route in `app.py`.
4. The route calls `BookingMcpService`.
5. `BookingMcpService` invokes the required MCP tool explicitly with either the traveler bearer token or the shared Basic Auth header, depending on `BACKEND_AUTH_MODE`.
6. The tool result is normalized and returned to the UI response.

When browser login is not required, the flow is the same except the UI uses a stored guest traveler profile and sends either a service OAuth token, a shared Basic Auth header, or no auth header depending on `BACKEND_AUTH_MODE`.

### Implementation Constraints

- The booking backend is the MCP server and its tools.
- The Python MCP client transport stays on `Streamable HTTP`.
- No agent-based orchestration is allowed in the booking path.

## Required Environment Variables

- Always:
  - `MCP_SERVER_URL`
  - `BACKEND_AUTH_MODE` optional
  - `PORT` optional, defaults to `8085`
  - `MCP_TIMEOUT_SECONDS` optional

- When `BACKEND_AUTH_MODE=basic`:
  - `BASIC_AUTH_USERNAME`
  - `BASIC_AUTH_PASSWORD`

- When `BACKEND_AUTH_MODE=oauth2`:
  - `OIDC_TOKEN_URL`
  - `OIDC_CLIENT_ID`
  - `OIDC_CLIENT_SECRET`
  - `OIDC_SCOPE` optional

- When `FRONTEND_AUTH_REQUIRED=true`:
  - `FLASK_SECRET_KEY`

If `BACKEND_AUTH_MODE` is not set, the legacy `OAUTH2_ENABLED` flag is still supported for backward compatibility.

The local compose stacks set the required values automatically.

## Compose Usage

Compose service name: `web_app_mcp`

- Local compose stack: see [../QUICKSTART.md](../QUICKSTART.md), option 1.
- VM/LAN OAuth host stack: see [../QUICKSTART.md](../QUICKSTART.md), option 2.
- Local Basic Auth stack: see [../local-container/README.md](../local-container/README.md), option 3.
- Keycloak UI + MCP Basic Auth stack: see [../QUICKSTART.md](../QUICKSTART.md), option 4.
- MCP-backed frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.yaml up --build \
    keycloak booking_system_mcp web_app_mcp
  ```

- MCP-backed Basic Auth frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.basic-auth.yaml up --build \
    booking_system_mcp web_app_mcp
  ```

- Keycloak login + MCP Basic Auth frontend path:

  ```sh
  docker compose --env-file ../local-container/basic-auth.env \
    -f ../local-container/docker_compose.yaml \
    -f ../local-container/docker_compose.mcp-ui-keycloak-basic.yaml \
    up --build keycloak booking_system_mcp web_app_mcp
  ```

Default compose URL: `http://localhost:8085`

## Related Docs

- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)
- Advanced deployment notes: [../docs/reference/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md](../docs/reference/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)
